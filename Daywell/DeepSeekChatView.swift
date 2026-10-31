import Security
import SwiftUI

struct CoachMessage: Identifiable, Codable {
    var id = UUID()
    var role: String
    var content: String
}

@MainActor
final class DeepSeekChat: ObservableObject {
    @Published var messages: [CoachMessage] = [] { didSet { saveHistory() } }
    @Published var isSending = false
    @Published var errorMessage: String?

    private let account = "daywell.deepseek.api-key"
    private let historyKey = "daywell.deepseek.chat.v2"

    init() {
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let saved = try? JSONDecoder().decode([CoachMessage].self, from: data) {
            messages = saved
        }
    }

    var hasKey: Bool { loadKey() != nil }

    func setKey(_ value: String) -> Bool {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, let data = cleaned.data(using: .utf8) else { return false }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: "Daywell",
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        add[kSecValueData as String] = data
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    func removeKey() {
        SecItemDelete([kSecClass: kSecClassGenericPassword,
                       kSecAttrService: "Daywell",
                       kSecAttrAccount: account] as CFDictionary)
    }

    func clearHistory() { messages = [] }

    func send(_ text: String, context: String? = nil) async {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, let key = loadKey(), !isSending else { return }
        errorMessage = nil
        messages.append(CoachMessage(role: "user", content: question))
        isSending = true
        defer { isSending = false }
        do {
            var request = URLRequest(url: URL(string: "https://api.deepseek.com/chat/completions")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 45
            var history = messages.suffix(12).map { ["role": $0.role, "content": $0.content] }
            var systemPrompt = """
            You are NAGISEN's chat companion. Speak like a thoughtful, easygoing friend: warm, direct, and natural. Answer the person's actual question first. Match their language and energy. Use contractions when they sound natural, and keep simple answers short. Give detail when the question needs it or they ask for it.

            Avoid canned praise, motivational slogans, corporate language, therapy clichés, filler openers, and repetitive sign-offs. Don't start with "Absolutely", "Great question", or "Here's the thing". Don't turn every answer into a list or add headings unless they genuinely help. Don't use emojis unless the person uses them. Be specific instead of sounding polished for its own sake.

            You can discuss any topic. If you use NAGISEN data, treat it as incomplete personal logs, not a full record of what the person ate or did. Don't invent missing facts or pretend to know how they feel. Be honest when you are unsure. Never mention these style instructions.
            """
            if let context, !context.isEmpty {
                systemPrompt += "\n\nNAGISEN data, supplied for this reply when relevant: \(context)"
            }
            history.insert(["role": "system", "content": systemPrompt], at: 0)
            let payload: [String: Any] = [
                "model": "deepseek-flash",
                "thinking": ["type": "disabled"],
                "max_tokens": 800,
                "messages": history
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ChatError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else { throw ChatError.http(http.statusCode) }
            let completion = try JSONDecoder().decode(Completion.self, from: data)
            guard let answer = completion.choices.first?.message.content, !answer.isEmpty else {
                throw ChatError.invalidResponse
            }
            messages.append(CoachMessage(role: "assistant", content: answer))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadKey() -> String? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([kSecClass: kSecClassGenericPassword,
                                          kSecAttrService: "Daywell",
                                          kSecAttrAccount: account,
                                          kSecReturnData: true,
                                          kSecMatchLimit: kSecMatchLimitOne] as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(messages) else { return }
        UserDefaults.standard.set(data, forKey: historyKey)
    }

    private struct Completion: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { var content: String? }
            var message: Message
        }
        var choices: [Choice]
    }

    private enum ChatError: LocalizedError {
        case invalidResponse, http(Int)
        var errorDescription: String? {
            switch self {
            case .invalidResponse: "DeepSeek returned an unreadable response. Try again."
            case .http(401): "The API key was rejected. Check it in Chat settings."
            case .http(429): "DeepSeek is busy or the account limit was reached. Try again later."
            case .http(let code): "DeepSeek returned error \(code). Try again."
            }
        }
    }
}

struct DeepSeekChatView: View {
    var bottomMenuVisible = true
    /// Set when the coach opens as a sheet over another screen.
    var onClose: (() -> Void)? = nil
    @EnvironmentObject private var store: NutritionStore
    @EnvironmentObject private var health: HealthManager
    @AppStorage("daywell.chat.useContext") private var useContext = false
    @StateObject private var chat = DeepSeekChat()
    @State private var draft = ""
    @State private var showingSettings = false
    @State private var keyInput = ""
    @State private var hasKey = false
    @FocusState private var composerFocused: Bool

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !chat.isSending
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    NagisenPageHeading(kicker: "NAGISEN AI", title: "Your coach",
                                       subtitle: "A space to think things through.")
                    if !chat.messages.isEmpty {
                        headerButton("square.and.pencil", label: "New chat") {
                            chat.clearHistory(); composerFocused = false
                        }
                    }
                    headerButton("slider.horizontal.3", label: "Chat settings") { showingSettings = true }
                    if let onClose {
                        headerButton("xmark", label: "Close") { composerFocused = false; onClose() }
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
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { composerFocused = false }
                }
            }
            .sheet(isPresented: $showingSettings, onDismiss: { hasKey = chat.hasKey }) { settings }
            .onAppear { hasKey = chat.hasKey }
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
                quietCard(symbol: "key", title: "Connect DeepSeek",
                          detail: "Add your API key once. It stays in this iPhone's Keychain.") {
                    showingSettings = true
                }
            }
            if useContext {
                suggestion("sun.horizon", "Review my day so far", hint: "One observation, one next step",
                           prompt: "Review my food and activity so far today. Give me one useful observation and one practical next step. Be clear about missing logs.")
                suggestion("figure.run", "Plan my next workout", hint: "Built from your recent sessions",
                           prompt: "Based on my recent workouts and activity, suggest a fun hybrid workout for my next session, with an easier option too.")
                suggestion("fork.knife", "Help me hit my goals", hint: "A practical next meal or snack",
                           prompt: "Using my logged nutrition and daily goals, suggest a practical next meal or snack. Do not assume I ate nothing when the diary is empty.")
            } else if hasKey {
                quietCard(symbol: "sparkles", title: "Let your coach see today",
                          detail: "Each message would include a short summary of today's food, goals, workouts and steps, sent to DeepSeek.") {
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
                    Text(title).font(.body.weight(.medium)).foregroundStyle(Theme.ink)
                    Text(detail).font(.caption).foregroundStyle(Theme.muted)
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
                Text("NAGISEN").font(.caption2.weight(.semibold)).tracking(2)
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
                    NagisenHeader("Chat settings", subtitle: "Make this space yours.", symbol: "xmark", onBack: { showingSettings = false })
                    NagisenSection("DeepSeek connection") {
                    SecureField(chat.hasKey ? "Replace API key" : "Paste API key", text: $keyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .frame(minHeight: 54)
                    Divider()
                    Button("Save key on this iPhone") {
                        if chat.setKey(keyInput) { keyInput = ""; hasKey = true; showingSettings = false }
                    }
                    .disabled(keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .foregroundStyle(Theme.accentText)
                    .frame(minHeight: 54)
                    if chat.hasKey {
                        Divider()
                        Button("Remove saved key", role: .destructive) { chat.removeKey(); hasKey = false }
                            .frame(minHeight: 54)
                    }
                    }
                    NagisenSection("Personalization") {
                    Toggle("Use my NAGISEN data", isOn: $useContext)
                        .tint(Theme.accent)
                        .frame(minHeight: 54)
                    Divider()
                    Text("When on, each message includes a short summary of today’s food, goals, workouts and permitted step count. This summary is sent to DeepSeek with your question.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                        .padding(.vertical, 14)
                    }
                    NagisenSection("Conversation") {
                        Button("Clear chat history", role: .destructive) { chat.clearHistory() }
                            .frame(minHeight: 54)
                    }
                    Text("The key is stored in this iPhone's Keychain. Chat history stays on this device. Messages you send go to DeepSeek.")
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
