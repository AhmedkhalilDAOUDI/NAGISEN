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
    @EnvironmentObject private var store: NutritionStore
    @EnvironmentObject private var health: HealthManager
    @AppStorage("daywell.chat.useContext") private var useContext = false
    @StateObject private var chat = DeepSeekChat()
    @State private var draft = ""
    @State private var showingSettings = false
    @State private var keyInput = ""
    @FocusState private var composerFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    NagisenPageHeading(kicker: "NAGISEN AI", title: "Your coach",
                                       subtitle: "A space to think things through.", accent: Theme.fat)
                    HStack(spacing: 8) {
                        Button { chat.clearHistory(); composerFocused = false } label: {
                            Image(systemName: "square.and.pencil")
                                .font(.body.weight(.medium))
                                .frame(width: 40, height: 40)
                                .nagisenGlass(in: Circle(), tint: Theme.surface.opacity(0.16))
                        }
                        .accessibilityLabel("New chat")
                        Button { showingSettings = true } label: {
                            Image(systemName: "gearshape")
                                .font(.body.weight(.medium))
                                .frame(width: 40, height: 40)
                                .nagisenGlass(in: Circle(), tint: Theme.surface.opacity(0.16))
                        }
                        .accessibilityLabel("Chat settings")
                    }
                }
                .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 12)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            if chat.messages.isEmpty {
                                welcome
                                coachPrompts
                            }
                            ForEach(chat.messages) { message in
                                HStack {
                                    if message.role == "user" { Spacer(minLength: 45) }
                                    Text(message.content)
                                        .font(.subheadline)
                                        .padding(15)
                                        .background(message.role == "user" ? Theme.red : Theme.surface,
                                                    in: RoundedRectangle(cornerRadius: 17))
                                        .foregroundStyle(message.role == "user" ? .white : Theme.ink)
                                    if message.role != "user" { Spacer(minLength: 45) }
                                }
                                .padding(.horizontal, 20)
                                .id(message.id)
                            }
                            if chat.isSending {
                                Label("Thinking…", systemImage: "ellipsis.bubble")
                                    .font(.caption).foregroundStyle(Theme.muted)
                            }
                            if let error = chat.errorMessage {
                                Text(error).font(.caption).foregroundStyle(.red)
                            }
                        }
                        .padding(.vertical, 20)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .scrollIndicators(.hidden)
                    .onChange(of: chat.messages.count) { _, _ in
                        if let last = chat.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                if useContext {
                    Label("Using your NAGISEN data in this chat", systemImage: "sparkles")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.accentText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                        .padding(.top, 6)
                }
                HStack(spacing: 10) {
                    TextField("Ask anything…", text: $draft, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($composerFocused)
                        .submitLabel(.send)
                        .onSubmit { send() }
                        .padding(12)
                        .nagisenGlass(in: RoundedRectangle(cornerRadius: 16), tint: Theme.surface.opacity(0.18))
                    Button { send() } label: {
                        Image(systemName: "arrow.up")
                            .font(.headline)
                            .frame(width: 42, height: 42)
                            .background(Theme.red, in: Circle())
                            .foregroundStyle(.white)
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chat.isSending)
                }
                .padding(14)
                .background(Theme.paper)
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
            .sheet(isPresented: $showingSettings) { settings }
            .onAppear { if !chat.hasKey { showingSettings = true } }
        }
    }

    private var welcome: some View {
        Text("A little help for the journey")
            .font(.system(size: 27, design: .serif))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
            .background(Theme.surface.opacity(0.52))
    }

    private var coachPrompts: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("YOUR COACH, ON CALL")
                .font(.caption2.weight(.semibold)).tracking(2)
                .foregroundStyle(Theme.muted)
            if useContext {
                Button("Review my day so far") {
                    sendPrompt("Review my food and activity so far today. Give me one useful observation and one practical next step. Be clear about missing logs.")
                }
                Button("Plan my next workout") {
                    sendPrompt("Based on my recent workouts and activity, suggest a fun hybrid workout for my next session, with an easier option too.")
                }
                Button("Help me hit my goals") {
                    sendPrompt("Using my logged nutrition and daily goals, suggest a practical next meal or snack. Do not assume I ate nothing when the diary is empty.")
                }
            } else {
                Text("Turn on personal coaching in Chat settings to let me use a short summary of your NAGISEN logs.")
                    .font(.subheadline).foregroundStyle(Theme.muted)
                Button("Set up personal coaching") { showingSettings = true }
                    .font(.subheadline.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(Theme.accentText)
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
        .background(Theme.surface.opacity(0.52))
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
                        if chat.setKey(keyInput) { keyInput = ""; showingSettings = false }
                    }
                    .disabled(keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .foregroundStyle(Theme.accentText)
                    .frame(minHeight: 54)
                    if chat.hasKey {
                        Divider()
                        Button("Remove saved key", role: .destructive) { chat.removeKey() }
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
