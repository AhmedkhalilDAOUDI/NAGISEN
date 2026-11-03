import Security
import SwiftUI

struct CoachMessage: Identifiable, Codable {
    var id = UUID()
    var role: String
    var content: String
}

/// The AI service the coach talks to, with the person's own API key. Every provider except
/// Anthropic speaks the OpenAI chat-completions format, so "Other" covers any compatible service.
enum CoachProvider: String, CaseIterable, Identifiable {
    case openAI, anthropic, gemini, deepSeek, mistral, openRouter, custom

    var id: String { rawValue }

    var name: String {
        switch self {
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic"
        case .gemini: "Google Gemini"
        case .deepSeek: "DeepSeek"
        case .mistral: "Mistral"
        case .openRouter: "OpenRouter"
        case .custom: String(localized: "Other (OpenAI-compatible)")
        }
    }

    var defaultModel: String {
        switch self {
        case .openAI: "gpt-5-mini"
        case .anthropic: "claude-opus-5-5"
        case .gemini: "gemini-2.5-flash"
        case .deepSeek: "deepseek-flash"
        case .mistral: "mistral-small-latest"
        case .openRouter: "openrouter/auto"
        case .custom: ""
        }
    }

    /// The chat endpoint; `custom` uses the base URL the person typed.
    func endpoint(customBase: String) -> URL? {
        switch self {
        case .openAI: URL(string: "https://api.openai.com/v1/chat/completions")
        case .anthropic: URL(string: "https://api.anthropic.com/v1/messages")
        case .gemini: URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")
        case .deepSeek: URL(string: "https://api.deepseek.com/chat/completions")
        case .mistral: URL(string: "https://api.mistral.ai/v1/chat/completions")
        case .openRouter: URL(string: "https://openrouter.ai/api/v1/chat/completions")
        case .custom:
            URL(string: customBase.trimmingCharacters(in: .whitespacesAndNewlines))
                .flatMap { $0.scheme == "https" || $0.host == "localhost" ? $0 : nil }
                .map { $0.path.hasSuffix("/chat/completions") ? $0 : $0.appending(path: "chat/completions") }
        }
    }

    /// Keychain entry per provider. DeepSeek keeps the name it always had, so saved keys still work.
    var keychainAccount: String {
        self == .deepSeek ? "nagisen.deepseek.api-key" : "nagisen.coach.key.\(rawValue)"
    }

    /// Builds the request for one reply. `messages` holds only user and assistant turns.
    func request(key: String, model: String, customBase: String, system: String,
                 messages: [[String: String]]) throws -> URLRequest {
        guard let url = endpoint(customBase: customBase) else { throw CoachError.badEndpoint }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload: [String: Any] = ["model": model]
        if self == .anthropic {
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
            payload["system"] = system
            payload["messages"] = messages
            // Room for the model's thinking plus a chat-length answer.
            payload["max_tokens"] = 4000
            payload["output_config"] = ["effort": "low"]
        } else {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            payload["messages"] = [["role": "system", "content": system]] + messages
            // OpenAI's newer models reject max_tokens; everyone else expects it.
            payload[self == .openAI ? "max_completion_tokens" : "max_tokens"] = self == .openAI ? 4000 : 800
            if self == .deepSeek { payload["thinking"] = ["type": "disabled"] }
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return request
    }

    /// Pulls the answer text out of a successful response.
    func answer(from data: Data) -> String? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let text: String?
        if self == .anthropic {
            text = (root["content"] as? [[String: Any]])?
                .filter { $0["type"] as? String == "text" }
                .compactMap { $0["text"] as? String }
                .joined()
        } else {
            text = ((root["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String
        }
        return text.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
    }
}

enum CoachError: LocalizedError {
    case badEndpoint, invalidResponse, http(Int, String), refused(Int, String, String)
    var errorDescription: String? {
        switch self {
        case .badEndpoint: String(localized: "The service address isn't valid. Check it in Chat settings.")
        case .invalidResponse: String(localized: "The AI service returned an unreadable response. Try again.")
        case .http(401, _), .http(403, _): String(localized: "The API key was rejected. Check it in Chat settings.")
        case .http(402, let name): String(localized: "Your \(name) account has no credit left.")
        case .http(404, _): String(localized: "The model wasn't found. Check the model name in Chat settings.")
        case .http(429, let name): String(localized: "\(name) is busy or your limit was reached. Try again later.")
        case .http(let code, let name): String(localized: "\(name) returned error \(code). Try again.")
        case .refused(let code, let name, let reason): String(localized: "\(name) returned error \(code): \(reason)")
        }
    }
}

@MainActor
final class CoachChat: ObservableObject {
    @Published var messages: [CoachMessage] = [] { didSet { saveHistory() } }
    @Published var isSending = false
    @Published var errorMessage: String?

    private let historyKey = "nagisen.deepseek.chat.v2"
    static let providerKey = "nagisen.coach.provider"
    static let baseURLKey = "nagisen.coach.baseURL"
    /// Set after a saved key was refused and the built-in one worked; cleared when you save a new key.
    static let preferBuiltInKey = "nagisen.coach.preferBuiltInKey"
    static func modelKey(_ provider: CoachProvider) -> String { "nagisen.coach.model.\(provider.rawValue)" }

    init() {
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let saved = try? JSONDecoder().decode([CoachMessage].self, from: data) {
            messages = saved
        }
    }

    /// The chosen provider. Someone who saved a DeepSeek key before providers existed stays on DeepSeek.
    var provider: CoachProvider {
        if let raw = UserDefaults.standard.string(forKey: Self.providerKey), let chosen = CoachProvider(rawValue: raw) {
            return chosen
        }
        return Self.loadKey(for: .deepSeek) != nil ? .deepSeek : .openAI
    }

    var model: String { Self.model(for: provider) }

    static func model(for provider: CoachProvider) -> String {
        let saved = UserDefaults.standard.string(forKey: modelKey(provider))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return saved.isEmpty ? provider.defaultModel : saved
    }

    var hasKey: Bool { Self.loadKey(for: provider) != nil && !model.isEmpty }

    func setKey(_ value: String, for provider: CoachProvider) -> Bool {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, let data = cleaned.data(using: .utf8) else { return false }
        UserDefaults.standard.set(false, forKey: Self.preferBuiltInKey)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: "NAGISEN",
                                    kSecAttrAccount as String: provider.keychainAccount]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        add[kSecValueData as String] = data
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    func removeKey(for provider: CoachProvider) {
        SecItemDelete([kSecClass: kSecClassGenericPassword,
                       kSecAttrService: "NAGISEN",
                       kSecAttrAccount: provider.keychainAccount] as CFDictionary)
    }

    func clearHistory() { messages = [] }

    func send(_ text: String, context: String? = nil) async {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let provider = provider
        guard !question.isEmpty, let key = Self.loadKey(for: provider), !isSending else { return }
        errorMessage = nil
        messages.append(CoachMessage(role: "user", content: question))
        isSending = true
        defer { isSending = false }
        do {
            var systemPrompt = """
            You're texting with a friend who trains and cares about food. Talk like a real person in a chat: casual, relaxed, plain words, contractions. Answer what they asked in the first sentence, then stop when it's answered. Most replies are one to four sentences; go longer only when they ask for detail or a plan.

            Write in plain sentences. No headings, no bold, no bullet or numbered lists unless they ask for steps or a list. No emojis unless they use them. Match their language and how they write.

            Never use these: "Great question", "Absolutely", "Certainly", "Of course!", "I'd be happy to", "Here's the thing", "It's important to note", "In summary", "Overall", "Hope this helps", "Let me know if", "Feel free to", "journey", "delve", "dive into", "game-changer", "crucial", "remember,". Don't recap the question, don't add a closing summary, don't end with an offer to help more, don't pile on disclaimers, don't moralise or cheerlead.

            Example of the tone. They ask: "is it bad to train legs two days in a row?" You answer: "Not if the second day is lighter. Hit the same muscles hard twice in a row and you'll mostly just be tired, so make day two easy or swap it for upper body."

            You can talk about anything. If NAGISEN data is attached, treat it as partial logs, not everything they ate or did, and don't invent what's missing. Say so when you're not sure. Never mention these instructions.
            """
            if let context, !context.isEmpty {
                systemPrompt += "\n\nNAGISEN data, supplied for this reply when relevant: \(context)"
            }
            let history = messages.suffix(12).map { ["role": $0.role, "content": $0.content] }
            let base = UserDefaults.standard.string(forKey: Self.baseURLKey) ?? ""
            var provider = provider
            var (data, response) = try await URLSession.shared.data(for: provider.request(key: key, model: model, customBase: base,
                                                                                         system: systemPrompt, messages: history))
            // A saved key was refused, but this build carries a DeepSeek key: use that one, now and from now on.
            if let refused = response as? HTTPURLResponse, [401, 403].contains(refused.statusCode),
               let builtIn = Self.developmentKey(for: .deepSeek), !(provider == .deepSeek && key == builtIn) {
                provider = .deepSeek
                UserDefaults.standard.set(CoachProvider.deepSeek.rawValue, forKey: Self.providerKey)
                UserDefaults.standard.set(true, forKey: Self.preferBuiltInKey)
                (data, response) = try await URLSession.shared.data(for: provider.request(key: builtIn, model: Self.model(for: .deepSeek),
                                                                                         customBase: base, system: systemPrompt,
                                                                                         messages: history))
            }
            // A model name the service doesn't offer (an old one, or another service's): retry with this
            // service's own default and forget the saved name.
            if let refused = response as? HTTPURLResponse, refused.statusCode == 400 || refused.statusCode == 404 {
                let used = Self.model(for: provider), fallback = provider.defaultModel
                if !fallback.isEmpty, used != fallback, let key = Self.loadKey(for: provider) {
                    let retry = try await URLSession.shared.data(for: provider.request(key: key, model: fallback, customBase: base,
                                                                                       system: systemPrompt, messages: history))
                    if let fixed = retry.1 as? HTTPURLResponse, (200..<300).contains(fixed.statusCode) {
                        UserDefaults.standard.removeObject(forKey: Self.modelKey(provider))
                    }
                    (data, response) = retry
                }
            }
            guard let http = response as? HTTPURLResponse else { throw CoachError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                // Most services explain a refusal in {"error": {"message": …}}; show that rather than only a number.
                if ![401, 403, 402, 429].contains(http.statusCode),
                   let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let reason = (body["error"] as? [String: Any])?["message"] as? String ?? body["message"] as? String,
                   !reason.isEmpty {
                    throw CoachError.refused(http.statusCode, provider.name, String(reason.prefix(200)))
                }
                throw CoachError.http(http.statusCode, provider.name)
            }
            guard let answer = provider.answer(from: data) else { throw CoachError.invalidResponse }
            messages.append(CoachMessage(role: "assistant", content: answer))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    static func loadKey(for provider: CoachProvider) -> String? {
        if UserDefaults.standard.bool(forKey: preferBuiltInKey), let builtIn = developmentKey(for: provider) { return builtIn }
        var result: CFTypeRef?
        let status = SecItemCopyMatching([kSecClass: kSecClassGenericPassword,
                                          kSecAttrService: "NAGISEN",
                                          kSecAttrAccount: provider.keychainAccount,
                                          kSecReturnData: true,
                                          kSecMatchLimit: kSecMatchLimitOne] as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return developmentKey(for: provider) }
        return String(data: data, encoding: .utf8)
    }

    /// The DeepSeek key built into Debug builds from Secrets.xcconfig, for the owner's own phone.
    /// A key saved in the Keychain always wins; Release builds never carry one.
    private static func developmentKey(for provider: CoachProvider) -> String? {
        #if DEBUG
        guard provider == .deepSeek,
              let key = Bundle.main.object(forInfoDictionaryKey: "DeepSeekDevKey") as? String,
              !key.isEmpty, !key.hasPrefix("$(") else { return nil }
        return key
        #else
        return nil
        #endif
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(messages) else { return }
        UserDefaults.standard.set(data, forKey: historyKey)
    }
}

struct DeepSeekChatView: View {
    var bottomMenuVisible = true
    /// Set when the coach opens as a sheet over another screen.
    var onClose: (() -> Void)? = nil
    @EnvironmentObject private var store: NutritionStore
    @EnvironmentObject private var health: HealthManager
    @AppStorage("nagisen.chat.useContext") private var useContext = false
    @StateObject private var chat = CoachChat()
    @State private var draft = ""
    @State private var showingSettings = false
    @State private var keyInput = ""
    @State private var hasKey = false
    @AppStorage(CoachChat.providerKey) private var providerRaw = ""
    @AppStorage(CoachChat.baseURLKey) private var customBase = ""
    @State private var modelInput = ""
    @FocusState private var composerFocused: Bool

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !chat.isSending
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    NagisenPageHeading(kicker: String(localized: "NAGISEN AI"), title: String(localized: "Your coach"),
                                       subtitle: String(localized: "A space to think things through."))
                    if !chat.messages.isEmpty {
                        headerButton("square.and.pencil", label: String(localized: "New chat")) {
                            chat.clearHistory(); composerFocused = false
                        }
                    }
                    headerButton("slider.horizontal.3", label: String(localized: "Chat settings")) { showingSettings = true }
                    if let onClose {
                        headerButton("xmark", label: String(localized: "Close")) { composerFocused = false; onClose() }
                    }
                }
                .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 4)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 22) {
                            if chat.messages.isEmpty {
                                emptyState
                            }
                            ForEach(chat.messages) { message in
                                Group {
                                    if message.role == "user" { userMessage(message) } else { coachMessage(message) }
                                }
                                .id(message.id)
                            }
                            if chat.isSending {
                                ThinkingDots().padding(.leading, 2).id("thinking")
                            }
                            if let error = chat.errorMessage {
                                Label(error, systemImage: "exclamationmark.circle")
                                    .font(.footnote).foregroundStyle(Theme.accentText)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 18)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .scrollIndicators(.hidden)
                    .onChange(of: chat.messages.count) { _, _ in
                        withAnimation(.smooth(duration: 0.25)) {
                            if let last = chat.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                    .onChange(of: chat.isSending) { _, sending in
                        if sending { withAnimation(.smooth(duration: 0.25)) { proxy.scrollTo("thinking", anchor: .bottom) } }
                    }
                }
                composer
            }
            .padding(.bottom, bottomMenuVisible ? 90 : 0)
            .background(NagisenBackdrop())
            .toolbar(.hidden, for: .navigationBar)
            // No keyboard "Done" bar: it floats over the send button. Swiping the messages down closes the keyboard.
            .sheet(isPresented: $showingSettings, onDismiss: { hasKey = chat.hasKey }) { settings }
            .onAppear { hasKey = chat.hasKey; modelInput = UserDefaults.standard.string(forKey: CoachChat.modelKey(chat.provider)) ?? "" }
        }
    }

    private func headerButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 38, height: 38)
                .nagisenGlass(in: Circle(), tint: Theme.surface.opacity(0.16))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.ink)
        .accessibilityLabel(label)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("What's on your mind?")
                    .font(.system(.title, design: .serif))
                Text(useContext ? "I can see today's logs, goals and recent training."
                                : "Ask about food, training, recovery or anything else.")
                    .font(.subheadline).foregroundStyle(Theme.muted)
            }
            .padding(.top, 18)

            if !hasKey {
                quietCard(symbol: "key", title: String(localized: "Connect an AI"),
                          detail: String(localized: "Pick OpenAI, Anthropic, Google or another service and add your own API key. It stays in this iPhone's Keychain.")) {
                    showingSettings = true
                }
            }
            if useContext {
                suggestion("sun.horizon", String(localized: "Review my day so far"), hint: String(localized: "One observation, one next step"),
                           prompt: "Review my food and activity so far today. Give me one useful observation and one practical next step. Be clear about missing logs.")
                suggestion("figure.run", String(localized: "Plan my next workout"), hint: String(localized: "Built from your recent sessions"),
                           prompt: "Based on my recent workouts and activity, suggest a fun hybrid workout for my next session, with an easier option too.")
                suggestion("fork.knife", String(localized: "Help me hit my goals"), hint: "A practical next meal or snack",
                           prompt: "Using my logged nutrition and daily goals, suggest a practical next meal or snack. Do not assume I ate nothing when the diary is empty.")
            } else if hasKey {
                quietCard(symbol: "sparkles", title: String(localized: "Let your coach see today"),
                          detail: String(localized: "Each message would include a short summary of today's food, goals, workouts and steps, sent to \(chat.provider.name).")) {
                    useContext = true
                }
            }
        }
        .foregroundStyle(Theme.ink)
    }

    private func suggestion(_ symbol: String, _ title: String, hint: String, prompt: String) -> some View {
        quietCard(symbol: symbol, title: title, detail: hint) { sendPrompt(prompt) }
    }

    private func quietCard(symbol: String, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(Theme.accentText)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(ui: title).font(.body.weight(.medium)).foregroundStyle(Theme.ink)
                    Text(ui: detail).font(.caption).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
            }
            .multilineTextAlignment(.leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .softCardStyle()
    }

    // MARK: - Messages

    private func userMessage(_ message: CoachMessage) -> some View {
        HStack {
            Spacer(minLength: 48)
            Text(message.content)
                .font(.body)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .nagisenGlass(in: RoundedRectangle(cornerRadius: 20), tint: Theme.accent.opacity(0.22))
                .textSelection(.enabled)
        }
    }

    private func coachMessage(_ message: CoachMessage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(Theme.red).frame(width: 6, height: 6)
                Text("NAGISEN").font(.caption2.weight(.semibold)).nagisenTracking(2)
            }
            .foregroundStyle(Theme.muted)
            Text(Self.rendered(message.content))
                .font(.body)
                .lineSpacing(4)
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Shows the bold, italics, code and links the model writes in Markdown, keeping its line breaks.
    static func rendered(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text,
                               options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if useContext {
                Label("Using today's NAGISEN data", systemImage: "sparkles")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.accentText)
                    .padding(.horizontal, 8)
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask anything", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($composerFocused)
                    .submitLabel(.send)
                    .onSubmit { send() }
                    .padding(.vertical, 10)
                    .padding(.leading, 6)
                Button { send() } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .background(canSend ? Theme.accent : Theme.muted.opacity(0.25), in: Circle())
                        .foregroundStyle(canSend ? .white : Theme.muted)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .animation(.easeOut(duration: 0.15), value: canSend)
                .accessibilityLabel("Send")
            }
            .padding(.leading, 12).padding(.trailing, 2).padding(.vertical, 2)
            .nagisenGlass(in: RoundedRectangle(cornerRadius: 24), tint: Theme.surface.opacity(0.22))
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background {
            LinearGradient(colors: [Theme.paper.opacity(0), Theme.paper.opacity(0.85)],
                           startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
        }
    }

    private var settings: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    NagisenHeader("Chat settings", subtitle: String(localized: "Make this space yours."), symbol: "xmark", onBack: { showingSettings = false })
                    NagisenSection("AI service") {
                    Picker("Service", selection: providerBinding) {
                        ForEach(CoachProvider.allCases) { Text(ui: $0.name).tag($0) }
                    }
                    .tint(Theme.accentText)
                    .frame(minHeight: 54)
                    Divider()
                    if chat.provider == .custom {
                        TextField("Base URL, like https://api.example.com/v1", text: $customBase)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .frame(minHeight: 54)
                        Divider()
                    }
                    TextField(chat.provider.defaultModel.isEmpty ? String(localized: "Model name") : chat.provider.defaultModel,
                              text: $modelInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .frame(minHeight: 54)
                        .onChange(of: modelInput) { _, value in
                            UserDefaults.standard.set(value, forKey: CoachChat.modelKey(chat.provider))
                            hasKey = chat.hasKey
                        }
                    Divider()
                    SecureField(CoachChat.loadKey(for: chat.provider) != nil ? "Replace API key" : "Paste API key", text: $keyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .frame(minHeight: 54)
                    Divider()
                    Button("Save key on this iPhone") {
                        if chat.setKey(keyInput, for: chat.provider) { keyInput = ""; hasKey = chat.hasKey; if hasKey { showingSettings = false } }
                    }
                    .disabled(keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .foregroundStyle(Theme.accentText)
                    .frame(minHeight: 54)
                    if CoachChat.loadKey(for: chat.provider) != nil {
                        Divider()
                        Button("Remove saved key", role: .destructive) { chat.removeKey(for: chat.provider); hasKey = false }
                            .foregroundStyle(Theme.danger)
                            .frame(minHeight: 54)
                    }
                    }
                    NagisenSection("Personalization") {
                    Toggle("Use my NAGISEN data", isOn: $useContext)
                        .tint(Theme.red)
                        .frame(minHeight: 54)
                    Divider()
                    Text("When on, each message includes a short summary of today’s food, goals, workouts and permitted step count. This summary is sent to \(chat.provider.name) with your question.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                        .padding(.vertical, 14)
                    }
                    NagisenSection("Conversation") {
                        Button("Clear chat history", role: .destructive) { chat.clearHistory() }
                            .foregroundStyle(Theme.danger)
                            .frame(minHeight: 54)
                    }
                    Text("The key is stored in this iPhone's Keychain. Chat history stays on this device. Messages you send go to \(chat.provider.name), under that service's own terms.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                        .padding(.horizontal, 2)
                }
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 32)
            }
            .background(NagisenBackdrop())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    /// Switching service loads that service's saved model and key state.
    private var providerBinding: Binding<CoachProvider> {
        Binding(get: { chat.provider }, set: { next in
            providerRaw = next.rawValue
            modelInput = UserDefaults.standard.string(forKey: CoachChat.modelKey(next)) ?? ""
            keyInput = ""
            hasKey = chat.hasKey
        })
    }

    private func send() {
        guard chat.hasKey else { showingSettings = true; return }
        let text = draft
        draft = ""
        composerFocused = false
        let context = useContext ? personalContext : nil
        Task { await chat.send(text, context: context) }
    }

    private func sendPrompt(_ prompt: String) {
        draft = prompt
        send()
    }

    private var personalContext: String {
        let totals = store.totals(on: .now)
        let todayGoals = store.goals(on: .now)
        let loggedMeals = store.entries(on: .now)
        let workouts = store.workouts.filter { Calendar.current.isDateInToday($0.date) }
        let recentTraining = store.workouts.sorted { $0.date > $1.date }.prefix(3)
            .map { "\($0.activity) \($0.minutes) min on \($0.date.formatted(date: .abbreviated, time: .omitted))" }
            .joined(separator: "; ")
        let todayFood = loggedMeals.map { "\($0.food.name) \($0.portionDescription)" }
            .joined(separator: "; ")
        let lastSevenDays = (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: .now) }
        let loggedDays = lastSevenDays.filter { !store.entries(on: $0).isEmpty }
        let averageLoggedCalories = loggedDays.isEmpty ? nil :
            loggedDays.reduce(0) { $0 + store.totals(on: $1).calories } / loggedDays.count
        var parts = [
            "Today's goals: \(todayGoals.calories) kcal, \(todayGoals.protein) g protein, \(todayGoals.carbs) g carbs, \(todayGoals.fat) g fat.",
            "Today: \(loggedMeals.count) food entries, \(totals.calories) kcal logged, \(Int(totals.protein.rounded())) g protein logged, \(workouts.count) NAGISEN workouts logged."
        ]
        if let steps = health.steps { parts.append("Apple Health steps today: \(steps).") }
        if !todayFood.isEmpty { parts.append("Foods logged today: \(todayFood).") }
        if let averageLoggedCalories {
            parts.append("Last 7 days: food logged on \(loggedDays.count) days; average \(averageLoggedCalories) kcal per logged day. Unlogged days are missing data.")
        }
        if !recentTraining.isEmpty { parts.append("Recent NAGISEN workouts: \(recentTraining).") }
        return parts.joined(separator: " ")
    }
}

/// Three dots that breathe while the coach writes; still when Reduce Motion is on.
private struct ThinkingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Theme.accentText)
                    .frame(width: 6, height: 6)
                    .opacity(reduceMotion ? 0.6 : (breathing ? 1 : 0.25))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.7).repeatForever().delay(Double(index) * 0.2),
                               value: breathing)
            }
        }
        .padding(.vertical, 6)
        .onAppear { breathing = true }
        .accessibilityElement()
        .accessibilityLabel("Your coach is writing")
    }
}
