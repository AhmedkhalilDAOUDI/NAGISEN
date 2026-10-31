import SwiftUI
import UIKit
import UserNotifications

enum Theme {
    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
    static let paper = adaptive(0xF9F7F2, 0x242427)
    static let surface = adaptive(0xFFFCF7, 0x343438)
    static let ink = adaptive(0x2F322C, 0xF0E8DB)
    static let muted = adaptive(0x716F69, 0xB8B0A7)
    static let line = adaptive(0xE2D9CC, 0x555258)
    static let red = adaptive(0xB85A2B, 0x74243A)
    static let accent = adaptive(0xB85A2B, 0x8B2B49)
    // Deep wine stays on filled controls; warm copper carries readable accent text in dark mode.
    static let accentText = adaptive(0xB85A2B, 0xE4AA82)
    static let moss = adaptive(0x777174, 0xAAA3A8)
    static let workout = adaptive(0xB85A2B, 0xB86677)
    static let gold = adaptive(0xB98654, 0xD6A875)
    /// Destructive actions: a muted rose instead of the system's alarm red.
    static let danger = adaptive(0xA8432F, 0xD27885)
    static let slate = adaptive(0x6E858B, 0xA9BFC5)
    static let protein = adaptive(0x377F77, 0x80C9BC)
    static let carbs = adaptive(0xB57726, 0xE1B76E)
    static let fat = adaptive(0x7E6394, 0xBCA2D1)
}

private extension Meal {
    var highlight: Color {
        switch self {
        case .breakfast: Theme.gold
        case .lunch: Theme.accent
        case .dinner: Theme.fat
        case .snacks: Theme.slate
        }
    }
}

struct NagisenBackdrop: View {
    var body: some View {
        Theme.paper.ignoresSafeArea().allowsHitTesting(false)
    }
}

private enum CalorieBalanceStyle {
    static func overage(_ eaten: Int, goal: Int) -> Int { max(0, eaten - goal) }

    static func overflowFraction(_ eaten: Int, goal: Int) -> CGFloat {
        min(CGFloat(overage(eaten, goal: goal)) / CGFloat(max(goal, 1)), 1)
    }

    static func color(_ eaten: Int, goal: Int) -> Color {
        let fraction = Double(overage(eaten, goal: goal)) / Double(max(goal, 1))
        if fraction <= 0 { return Theme.red }
        if fraction < 0.10 { return Theme.gold }
        if fraction < 0.25 {
            return Color(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 0.84, green: 0.36, blue: 0.39, alpha: 1)
                    : UIColor(red: 0.72, green: 0.35, blue: 0.17, alpha: 1)
            })
        }
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.96, green: 0.42, blue: 0.39, alpha: 1)
                : UIColor(red: 0.70, green: 0.23, blue: 0.19, alpha: 1)
        })
    }
}

extension AppearanceMode {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

private struct AddContext: Identifiable {
    let id = UUID()
    let date: Date
    let meal: Meal
}

struct ContentView: View {
    @EnvironmentObject private var store: NutritionStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var addContext: AddContext?
    @State private var selectedDate = Date.now
    @State private var section: MainSection = .launchSection
    @State private var showingCoach = MainSection.launchOpensCoach
    @State private var showingIntro = true
    @State private var slideDirection: CGFloat = 1
    @State private var keyboardVisible = false

    var body: some View {
        ZStack {
            NagisenBackdrop()
            selectedSectionView
                .ignoresSafeArea(.container, edges: .bottom)
                .id(section)
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .offset(x: slideDirection * 72).combined(with: .opacity),
                    removal: .offset(x: -slideDirection * 72).combined(with: .opacity)
                ))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .softTopScrollEdgeEffect()
        .overlay(alignment: .bottom) {
            if !keyboardVisible {
                ZStack(alignment: .bottom) {
                    LinearGradient(stops: [.init(color: Theme.paper.opacity(0), location: 0),
                                           .init(color: Theme.paper.opacity(0.78), location: 0.55),
                                           .init(color: Theme.paper.opacity(0.92), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 130)
                        .ignoresSafeArea(edges: .bottom)
                        .allowsHitTesting(false)
                    BottomGlassMenu(section: section, onSelect: selectSection, onOpenCoach: { showingCoach = true })
                }
            }
        }
        .overlay {
            if showingIntro { LaunchIntroView { showingIntro = false }.ignoresSafeArea() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
        .background { NagisenBackdrop() }
        .toolbarBackground(.hidden, for: .navigationBar)
        .tint(Theme.accentText)
        .preferredColorScheme(store.appearance.colorScheme)
        .sheet(isPresented: $showingCoach) {
            DeepSeekChatView(bottomMenuVisible: false, onClose: { showingCoach = false })
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $addContext) { context in
            NavigationStack {
                FoodSearchView(date: context.date, initialMeal: context.meal)
            }
        }
    }

    @ViewBuilder private var selectedSectionView: some View {
        switch section {
        case .dashboard:
            HomeView(date: $selectedDate) { meal in
                addContext = AddContext(date: selectedDate, meal: meal)
            }
        case .grocery:
            NavigationStack { GroceryPlannerView(showBackButton: false) }
        case .workouts:
            WorkoutMusicView()
        case .feed:
            SocialFeedView()
        }
    }

    private func selectSection(_ next: MainSection) {
        guard next != section,
              let currentIndex = MainSection.allCases.firstIndex(of: section),
              let nextIndex = MainSection.allCases.firstIndex(of: next) else { return }
        slideDirection = nextIndex > currentIndex ? 1 : -1
        withAnimation(reduceMotion ? .easeInOut(duration: 0.12) : .smooth(duration: 0.32)) {
            section = next
        }
    }

}

private struct BottomGlassMenu: View {
    let section: MainSection
    let onSelect: (MainSection) -> Void
    let onOpenCoach: () -> Void
    @Namespace private var selectionAnimation

    private func isCurrent(_ item: MainSection) -> Bool { section == item }

    var body: some View {
        HStack(spacing: 8) {
            tabs
            coachButton
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    /// The AI coach, one tap away from every screen; it opens over whatever you're doing.
    private var coachButton: some View {
        Button(action: onOpenCoach) {
            Image(systemName: "sparkles")
                .font(.system(size: 21, weight: .regular))
                .foregroundStyle(Theme.accentText)
                .frame(width: 71, height: 71)
                .background { glass(Circle()) }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("NAGISEN AI coach")
    }

    @ViewBuilder
    private func glass<S: InsettableShape>(_ shape: S) -> some View {
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(.regular.tint(Theme.paper.opacity(0.30)), in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.20), lineWidth: 0.7))
        } else {
            shape
                .fill(.ultraThinMaterial)
                .overlay(shape.fill(Theme.paper.opacity(0.30)))
                .overlay(shape.strokeBorder(.white.opacity(0.18), lineWidth: 0.7))
        }
    }

    private var tabs: some View {
        HStack(spacing: 2) {
            ForEach(MainSection.bottomSections) { item in
                Button {
                    onSelect(item)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 21, weight: isCurrent(item) ? .semibold : .regular))
                            .frame(height: 24)
                        Text(item.name)
                            .font(.system(size: 10, weight: isCurrent(item) ? .semibold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .foregroundStyle(isCurrent(item) ? Theme.accentText : Theme.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 61)
                    .background {
                        if isCurrent(item) {
                            Capsule()
                                .fill(Theme.accent.opacity(0.13))
                                .overlay(Capsule().strokeBorder(Theme.accentText.opacity(0.28), lineWidth: 0.7))
                                .matchedGeometryEffect(id: "selectedSection", in: selectionAnimation)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.name)
                .accessibilityAddTraits(isCurrent(item) ? .isSelected : [])
            }
        }
        .padding(.horizontal, 5)
        .padding(.top, 5)
        .padding(.bottom, 5)
        .background { glass(Capsule()) }
    }
}

private enum MainSection: String, CaseIterable, Identifiable {
    case dashboard, grocery, workouts, feed
    var id: Self { self }
    static let bottomSections: [MainSection] = [.dashboard, .grocery, .workouts, .feed]

    /// Dashboard. Debug builds launched with `-NAGISENSection feed` (or grocery, workouts)
    /// open on that tab instead, so screens can be captured without tapping; `ai` opens the coach.
    static var launchSection: MainSection {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-NAGISENSection"), index + 1 < arguments.count,
           let section = MainSection(rawValue: arguments[index + 1]) {
            return section
        }
        #endif
        return .dashboard
    }

    static var launchOpensCoach: Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-NAGISENSection"), index + 1 < arguments.count {
            return arguments[index + 1] == "ai"
        }
        #endif
        return false
    }
    var name: String {
        switch self {
        case .dashboard: "Dashboard"
        case .grocery: "Lab"
        case .workouts: "Workouts"
        case .feed: "Feed"
        }
    }
    var symbol: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .grocery: "basket"
        case .workouts: "figure.run"
        case .feed: "person.2"
        }
    }
}

private struct HomeView: View {
    @EnvironmentObject private var store: NutritionStore
    @EnvironmentObject private var health: HealthManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingCalendar = false
    @State private var showingProfile = false
    @Binding var date: Date
    let onAdd: (Meal) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.paper.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 9) {
                            HStack(spacing: 8) {
                                Circle().fill(Theme.red).frame(width: 10, height: 10)
                                Text("NAGISEN")
                                    .font(.caption.weight(.semibold)).tracking(3)
                            }
                            HStack(spacing: 4) {
                                Button { shiftDate(-1) } label: {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 16, weight: .medium))
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .padding(.horizontal, -7)
                                .accessibilityLabel("Previous day")
                                Button { showingCalendar = true } label: {
                                    HStack(spacing: 7) {
                                        Text(Calendar.current.isDateInToday(date) ? "Today" : date.formatted(.dateTime.month(.abbreviated).day()))
                                            .font(.system(size: 38, weight: .regular, design: .serif))
                                        Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                                    }
                                }
                                .accessibilityLabel("Choose calendar day")
                                Button { shiftDate(1) } label: {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 16, weight: .medium))
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .padding(.horizontal, -7)
                                .disabled(Calendar.current.isDateInToday(date))
                                .accessibilityLabel("Next day")
                            }
                            .buttonStyle(.plain)
                            Text(date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                                .font(.subheadline).foregroundStyle(Theme.muted)
                        }
                        Spacer(minLength: 3)
                        VStack(spacing: 4) {
                            HStack(spacing: -5) {
                                Button {
                                    store.appearance = colorScheme == .dark ? .light : .dark
                                } label: {
                                    Image(systemName: colorScheme == .dark ? "moon.fill" : "sun.max.fill")
                                        .font(.system(size: 17, weight: .regular))
                                        .frame(width: 34, height: 34)
                                        .nagisenGlass(in: Circle(), tint: Theme.surface.opacity(0.16))
                                        .frame(width: 44, height: 44)
                                        .contentShape(Circle())
                                }
                                .accessibilityLabel(colorScheme == .dark ? "Turn off dark mode" : "Turn on dark mode")
                                Button { showingProfile = true } label: {
                                    Image(systemName: "person.crop.circle")
                                        .font(.system(size: 16, weight: .medium))
                                        .frame(width: 34, height: 34)
                                        .nagisenGlass(in: Circle(), tint: Theme.surface.opacity(0.16))
                                        .frame(width: 44, height: 44)
                                        .contentShape(Circle())
                                }
                                .accessibilityLabel("You")
                            }
                            NavigationLink {
                                HealthView()
                            } label: {
                                Group {
                                    if health.hasRequestedAccess {
                                        VStack(spacing: 2) {
                                            Text(health.steps.map { $0.formatted() } ?? "—")
                                                .font(.system(size: 24, weight: .regular, design: .serif))
                                                .foregroundStyle(Theme.ink)
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.75)
                                            Text("STEPS")
                                                .font(.system(size: 10, weight: .medium))
                                                .tracking(2)
                                                .foregroundStyle(Theme.muted)
                                        }
                                    } else {
                                        // Falls back to the icon alone when large text leaves no room for the words.
                                        ViewThatFits(in: .horizontal) {
                                            Label("Connect steps", systemImage: "figure.walk")
                                                .lineLimit(1)
                                            Image(systemName: "figure.walk")
                                        }
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Theme.accentText)
                                        .frame(minHeight: 44)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                            }
                            .accessibilityLabel("Today’s steps: \(health.steps.map { $0.formatted() } ?? "connect Apple Health")")
                        }
                        .frame(width: 122)
                    }
                    .padding(.horizontal, 18)
                    // The header keeps its shape at the largest text sizes; the cards below scale freely.
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    VStack(alignment: .leading, spacing: 22) {
                        CalorieCard(date: date)
                        Rectangle().fill(Theme.line).frame(height: 1)
                        MacroCard(date: date)
                        Rectangle().fill(Theme.line).frame(height: 1)
                        WaterCard(date: date)
                    }
                    .cardStyle()
                    .padding(.horizontal, 18)
                    CreatineCard(date: date)
                        .padding(.horizontal, 18)
                    CaffeineCard(date: date)
                        .padding(.horizontal, 18)
                    CostCard(date: date)
                        .padding(.horizontal, 18)
                    HStack {
                        Text("Meals").font(.system(size: 25, design: .serif))
                        Spacer()
                        Text(date.formatted(.dateTime.month(.abbreviated).day()).uppercased())
                            .font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, 18)
                    ForEach(Meal.allCases) { meal in
                        MealCard(meal: meal, date: date) { onAdd(meal) }
                            .padding(.horizontal, 18)
                    }
                }
                .foregroundStyle(Theme.ink)
                .padding(.top, 24)
                .padding(.bottom, 100)
            }
            .scrollClipDisabled()
            .softTopScrollEdgeEffect()
            .scrollIndicators(.hidden)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingCalendar) {
                CalendarLogView(date: $date)
            }
            .sheet(isPresented: $showingProfile) {
                ProfileView()
            }
            }
        }
    }

    private func shiftDate(_ days: Int) {
        let calendar = Calendar.current
        guard let next = calendar.date(byAdding: .day, value: days, to: date),
              calendar.startOfDay(for: next) <= calendar.startOfDay(for: .now) else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
            date = next
        }
    }
}

struct DailyGuidanceCard: View {
    @EnvironmentObject private var store: NutritionStore
    @EnvironmentObject private var health: HealthManager

    private struct Cue: Identifiable {
        let title: String
        let detail: String
        let symbol: String
        var id: String { title }
    }

    private var cues: [Cue] {
        let today = Date.now
        let totals = store.totals(on: today)
        let remaining = store.goals(on: today).calories - totals.calories
        let proteinLeft = max(0, store.goals(on: today).protein - Int(totals.protein.rounded()))
        var result: [Cue] = []

        if totals.calories > 0 && proteinLeft >= 20 && remaining >= 150 {
            let eatenNames = Set(store.entries(on: today).map { $0.food.name.lowercased() })
            let candidates = store.recentFoods().filter {
                $0.protein >= 15 && $0.calories <= remaining && $0.calories > 0 &&
                !eatenNames.contains($0.name.lowercased())
            }
            if let food = candidates.first {
                result.append(Cue(title: "A familiar protein pick",
                                  detail: "\(food.name) gives about \(Int(food.protein.rounded())) g protein for \(food.calories) kcal per serving.",
                                  symbol: "fork.knife"))
            } else {
                result.append(Cue(title: "Room for protein",
                                  detail: "About \(proteinLeft) g remains toward your protein goal today.",
                                  symbol: "circle.dotted"))
            }
        }

        let calendar = Calendar.current
        let weekStart = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: today)) ?? today
        let trainedDays = Set(store.workouts.filter { $0.date >= weekStart }.map { store.dayKey($0.date) }).count
        if trainedDays >= 2 {
            result.append(Cue(title: "Your training rhythm",
                              detail: "You logged workouts on \(trainedDays) of the last 7 days. Keep the streak yours.",
                              symbol: "figure.run"))
        } else if let steps = health.steps, steps > 0 {
            result.append(Cue(title: "Movement is adding up",
                              detail: "\(steps.formatted()) steps so far today, from Apple Health.",
                              symbol: "figure.walk"))
        }

        if !store.creatineTaken(on: today) && calendar.component(.hour, from: today) >= 18 {
            result.append(Cue(title: "Evening check-in",
                              detail: "Your 5 g creatine switch is still off for today. Mark it when taken.",
                              symbol: "checkmark.circle"))
        }

        if result.isEmpty {
            let pastDays = Set(store.entries.filter { $0.date < calendar.startOfDay(for: today) }
                .map { store.dayKey($0.date) }).count
            if pastDays > 0 && totals.calories == 0 {
                result.append(Cue(title: "Start with what you know",
                                  detail: "Your recent foods are ready on Dashboard for a quick first entry today.",
                                  symbol: "clock.arrow.circlepath"))
            } else {
                result.append(Cue(title: "Your day, in focus",
                                  detail: "Log a meal or workout and NAGISEN will spot useful patterns here.",
                                  symbol: "sparkle.magnifyingglass"))
            }
        }
        return Array(result.prefix(2))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("TODAY'S INSIGHTS")
                    .font(.caption2.weight(.semibold)).tracking(2)
                    .foregroundStyle(Theme.muted)
                Spacer()
                Image(systemName: "sparkles").foregroundStyle(Theme.accentText)
            }
            ForEach(cues) { cue in
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: cue.symbol)
                        .font(.subheadline)
                        .foregroundStyle(Theme.accentText)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(cue.title).font(.subheadline.weight(.semibold))
                        Text(cue.detail).font(.caption).foregroundStyle(Theme.muted)
                    }
                }
            }
            Text("Based on your NAGISEN logs and permitted Health data · on this iPhone")
                .font(.system(size: 10)).foregroundStyle(Theme.muted)
        }
        .cardStyle()
    }
}

private struct CalendarLogView: View {
    @EnvironmentObject private var store: NutritionStore
    @Environment(\.dismiss) private var dismiss
    @Binding var date: Date
    @State private var displayedMonth: Date

    init(date: Binding<Date>) {
        self._date = date
        let selected = date.wrappedValue
        self._displayedMonth = State(initialValue: Calendar.current.date(
            from: Calendar.current.dateComponents([.year, .month], from: selected)) ?? selected)
    }

    private var monthDays: [Date?] {
        let calendar = Calendar.current
        guard let range = calendar.range(of: .day, in: .month, for: displayedMonth) else { return [] }
        let leading = (calendar.component(.weekday, from: displayedMonth) + 5) % 7
        let dates = range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: displayedMonth) }
        return Array(repeating: nil, count: leading) + dates.map(Optional.some)
    }

    private var canGoForward: Bool {
        Calendar.current.compare(displayedMonth, to: .now, toGranularity: .month) == .orderedAscending
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    NagisenHeader("Calendar & logs", subtitle: "Your days, in view.", symbol: "xmark", onBack: { dismiss() })
                    VStack(spacing: 17) {
                        HStack {
                            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                                .accessibilityLabel("Previous month")
                            Spacer()
                            Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                                .font(.system(size: 21, design: .serif))
                            Spacer()
                            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                                .disabled(!canGoForward)
                                .accessibilityLabel("Next month")
                        }
                        HStack {
                            ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) { day in
                                Text(day).font(.caption2.weight(.medium)).foregroundStyle(Theme.muted)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 10) {
                            ForEach(0..<monthDays.count, id: \.self) { index in
                                if let day = monthDays[index] {
                                    Button { date = day } label: {
                                        CalendarDayCell(day: day, selected: Calendar.current.isDate(day, inSameDayAs: date))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(day > .now)
                                } else {
                                    Color.clear.frame(height: 69)
                                }
                            }
                        }
                        HStack {
                            Text("Rings show calorie goal progress. Checks mark finished days.")
                                .font(.caption).foregroundStyle(Theme.muted)
                            Spacer()
                            Button("Today") {
                                date = .now
                                displayedMonth = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: .now)) ?? .now
                            }
                            .font(.caption.weight(.semibold))
                        }
                    }
                    .tint(Theme.accentText)
                    .padding(16)
                    .nagisenGlass(in: RoundedRectangle(cornerRadius: 18), tint: Theme.surface.opacity(0.18))
                    let entries = store.entries(on: date)
                    Text("\(date.formatted(.dateTime.weekday(.wide).month(.wide).day())) · \(store.totals(on: date).calories) kcal")
                        .font(.system(size: 20, design: .serif))
                    if entries.isEmpty {
                        Text("No food logged for this day")
                            .foregroundStyle(Theme.muted)
                            .cardStyle()
                    } else {
                        ForEach(Meal.allCases) { meal in
                            let items = entries.filter { $0.meal == meal }
                            if !items.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(meal.rawValue).font(.system(size: 18, design: .serif))
                                    ForEach(items) { item in
                                        HStack {
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(item.food.name)
                                                Text(item.portionDescription).font(.caption).foregroundStyle(Theme.muted)
                                            }
                                            Spacer()
                                            Text("\(item.calories) kcal").foregroundStyle(Theme.muted)
                                        }
                                    }
                                }
                                .cardStyle()
                            }
                        }
                    }
                    let workouts = store.workouts.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
                    if !workouts.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Workouts").font(.system(size: 18, design: .serif))
                            ForEach(workouts) { workout in
                                HStack {
                                    Text(workout.activity)
                                    Spacer()
                                    Text("\(workout.minutes) min").foregroundStyle(Theme.muted)
                                }
                            }
                        }
                        .cardStyle()
                    }
                }
                .foregroundStyle(Theme.ink)
                .padding(20)
            }
            .background(NagisenBackdrop())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func shiftMonth(_ value: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: value, to: displayedMonth) {
            displayedMonth = next
        }
    }
}

private struct CalendarDayCell: View {
    @EnvironmentObject private var store: NutritionStore
    let day: Date
    let selected: Bool

    var body: some View {
        let eaten = store.totals(on: day).calories
        let available = store.goals(on: day).calories
        let hasLogs = !store.entries(on: day).isEmpty
        // A tick means the day is finished, which is what the streak counts — not merely that
        // food was entered. Migrated days carry the tick with no food, and they belong here too.
        let finished = store.isLoggingComplete(on: day)
        let progress = min(CGFloat(eaten) / CGFloat(max(available, 1)), 1)
        let overage = CalorieBalanceStyle.overage(eaten, goal: available)
        VStack(spacing: 4) {
            Text("\(Calendar.current.component(.day, from: day))")
                .font(.caption.weight(selected ? .bold : .medium))
                .foregroundStyle(selected ? Theme.accentText : Theme.ink)
            ZStack {
                Circle().stroke(Theme.line, lineWidth: 4)
                Circle().trim(from: 0, to: progress)
                    .stroke(overage > 0 ? CalorieBalanceStyle.color(eaten, goal: available).opacity(0.45) : Theme.red,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if overage > 0 {
                    Circle().trim(from: 0, to: CalorieBalanceStyle.overflowFraction(eaten, goal: available))
                        .stroke(CalorieBalanceStyle.color(eaten, goal: available),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(6)
                }
                if overage > 0 {
                    Image(systemName: "plus")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(CalorieBalanceStyle.color(eaten, goal: available))
                } else if finished {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.accentText)
                }
            }
            .frame(width: 36, height: 36)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 65)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Theme.accent : .clear, lineWidth: 1.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(day.formatted(date: .abbreviated, time: .omitted)), \(eaten) calories\(overage > 0 ? ", \(overage) calories over goal" : (finished ? ", finished logging" : (hasLogs ? ", food logged" : "")))")
    }
}

private struct CalorieCard: View {
    @EnvironmentObject private var store: NutritionStore
    let date: Date
    @State private var showingStreakAudit = false
    @State private var celebrating = false

    var body: some View {
        let eaten = store.totals(on: date).calories
        let goal = store.goals(on: date).calories
        let bonus = store.weeklyCalorieBonus(on: date)
        let remaining = goal - eaten
        let overage = CalorieBalanceStyle.overage(eaten, goal: goal)
        let balanceColor = CalorieBalanceStyle.color(eaten, goal: goal)
        VStack(alignment: .leading, spacing: 18) {
            Text("DAILY BALANCE")
                .font(.caption2.weight(.semibold)).tracking(2.2)
                .foregroundStyle(Theme.muted)
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(abs(remaining).formatted())
                        .font(.system(size: 53, weight: .light, design: .serif))
                        .minimumScaleFactor(0.75)
                        .lineLimit(1)
                        .foregroundStyle(Theme.ink)
                    Text(remaining >= 0 ? "kcal remaining" : "kcal over goal")
                        .font(.subheadline).foregroundStyle(overage > 0 ? Theme.ink : Theme.muted)
                }
                Spacer(minLength: 0)
                ZStack {
                    Circle().stroke(Theme.line, lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: min(CGFloat(eaten) / CGFloat(max(goal, 1)), 1))
                        .stroke(overage > 0 ? balanceColor.opacity(0.38) : Theme.red,
                                style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    if overage > 0 {
                        Circle()
                            .trim(from: 0, to: CalorieBalanceStyle.overflowFraction(eaten, goal: goal))
                            .stroke(balanceColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .padding(10)
                        VStack(spacing: 0) {
                            Text("+\(overage.formatted())")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .minimumScaleFactor(0.65).lineLimit(1)
                            Text("OVER")
                                .font(.system(size: 7, weight: .bold)).tracking(1)
                        }
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 19)
                    } else {
                        Image(systemName: "flame")
                            .font(.title3.weight(.light)).foregroundStyle(Theme.accentText)
                    }
                }
                .frame(width: 92, height: 92)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(overage > 0 ? "\(overage) calories over goal" : "\(eaten) of \(goal) calories eaten")
            }
            if bonus > 0 {
                HStack(alignment: .firstTextBaseline) {
                    Text("Bonus calories")
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    Text("\(bonus.formatted()) kcal")
                        .foregroundStyle(Theme.ink)
                }
                .font(.subheadline.weight(.medium))
            }
            Rectangle().fill(Theme.line).frame(height: 1)
            VStack(alignment: .leading, spacing: 12) {
                let streak = store.streakSnapshot(asOf: date)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: streak.activeStreak > 0 ? "flame.fill" : "flame")
                        .foregroundStyle(streak.activeStreak > 0 ? Theme.accentText : Theme.muted)
                        .symbolEffect(.bounce, value: streak.activeStreak)
                        .accessibilityHidden(true)
                    Text("\(streak.activeStreak.formatted(.number.grouping(.automatic)))-day streak")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .contentTransition(.numericText(value: Double(streak.activeStreak)))
                    Spacer()
                    Button("Verify") { showingStreakAudit = true }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accentText)
                }
                Toggle(isOn: Binding(
                    get: { store.isLoggingComplete(on: date) },
                    set: { done in
                        store.setLoggingComplete(done, on: date)
                        if done && Calendar.current.isDateInToday(date) { celebrating = true }
                    }
                )) {
                    Label("Done Logging", systemImage: store.isLoggingComplete(on: date) ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.ink)
                        .labelStyle(.titleAndIcon)
                }
                .tint(Theme.accentText)
                .disabled(Calendar.current.startOfDay(for: date) > Calendar.current.startOfDay(for: .now))
            }
            .animation(.snappy, value: store.streakSnapshot(asOf: date).activeStreak)
            .sensoryFeedback(.success, trigger: store.streakSnapshot(asOf: date).activeStreak) { old, new in new > old }
        }
        .sheet(isPresented: $showingStreakAudit) {
            StreakAuditView().environmentObject(store)
        }
        .fullScreenCover(isPresented: $celebrating) {
            StreakCelebrationView(streak: store.streakSnapshot(asOf: date).activeStreak, date: date)
                .environmentObject(store)
                .presentationBackground(.black.opacity(0.5))
        }
        #if DEBUG
        .onAppear {
            // Test-only: lets the audit be captured without tapping through the UI.
            if ProcessInfo.processInfo.arguments.contains("-NAGISENOpenAudit") {
                showingStreakAudit = true
            }
            if ProcessInfo.processInfo.arguments.contains("-NAGISENCelebrate") { celebrating = true }
        }
        #endif
    }
}

private struct MacroCard: View {
    @EnvironmentObject private var store: NutritionStore
    @Environment(\.dynamicTypeSize) private var typeSize
    let date: Date

    var body: some View {
        let totals = store.totals(on: date)
        VStack(alignment: .leading, spacing: 17) {
            Text("NUTRITION")
                .font(.caption2.weight(.semibold)).tracking(2.2)
                .foregroundStyle(Theme.muted)
            // Side by side normally; stacked at accessibility text sizes so the columns never collide.
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 20))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
            layout {
                MacroRow(name: "Protein", amount: totals.protein, goal: store.goals(on: date).protein, color: Theme.protein)
                MacroRow(name: "Carbs", amount: totals.carbs, goal: store.goals(on: date).carbs, color: Theme.carbs)
                MacroRow(name: "Fat", amount: totals.fat, goal: store.goals(on: date).fat, color: Theme.fat)
            }
            if totals.incompleteMacroEntries > 0 {
                Text("\(totals.incompleteMacroEntries) food entry has missing macro data; these totals may be low.")
                    .font(.caption2).foregroundStyle(Theme.accentText)
            }
        }
    }
}

private struct CreatineCard: View {
    @EnvironmentObject private var store: NutritionStore
    let date: Date

    var body: some View {
        let taken = store.creatineTaken(on: date)
        HStack(spacing: 14) {
            Image(systemName: taken ? "checkmark.circle.fill" : "circle.dotted")
                .font(.title2)
                .foregroundStyle(Theme.accentText)
            VStack(alignment: .leading, spacing: 4) {
                Text("5g creatine").font(.system(.body, design: .serif))
                Text(taken ? "Taken on this day" : "Not taken on this day")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer()
            Toggle("Creatine taken on this day", isOn: Binding(
                get: { store.creatineTaken(on: date) },
                set: { store.setCreatineTaken($0, on: date) }
            ))
            .labelsHidden()
            .tint(Theme.red)
        }
        .cardStyle()
    }
}

private struct WaterCard: View {
    @EnvironmentObject private var store: NutritionStore
    @State private var showingDetails = false
    let date: Date

    var body: some View {
        let total = store.waterTotal(on: date)
        let goal = max(store.waterGoalML, 1)
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("WATER", systemImage: "drop.fill")
                    .font(.caption2.weight(.semibold)).tracking(2)
                    .foregroundStyle(Theme.accentText)
                Spacer()
                Button("Edit") { showingDetails = true }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accentText)
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(total.formatted())
                    .font(.system(size: 34, weight: .light, design: .serif))
                Text("/ \(goal.formatted()) mL")
                    .font(.subheadline).foregroundStyle(Theme.muted)
                Spacer()
                Text("\(Int(Double(total) / Double(goal) * 100))%")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accentText)
            }
            ProgressView(value: Double(min(total, goal)), total: Double(goal))
                .tint(Theme.red)
            HStack(spacing: 9) {
                Button("+ 250 mL") { store.addWater(250, on: date) }
                Button("+ 500 mL") { store.addWater(500, on: date) }
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
            .tint(Theme.red)
        }
        .sheet(isPresented: $showingDetails) {
            NavigationStack { WaterDetailView(date: date) }
        }
    }
}

private struct WaterDetailView: View {
    @EnvironmentObject private var store: NutritionStore
    @Environment(\.dismiss) private var dismiss
    let date: Date
    @State private var amount = ""
    @State private var goal = ""
    @AppStorage("daywell.water.reminders") private var remindersEnabled = false
    @State private var reminderError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                NagisenHeader("Water", subtitle: date.formatted(date: .complete, time: .omitted), symbol: "xmark", onBack: { dismiss() })
                NagisenSection("Daily progress") {
                HStack {
                    Image(systemName: "drop.fill").foregroundStyle(Theme.accentText)
                    Text("\(store.waterTotal(on: date).formatted()) of \(store.waterGoalML.formatted()) mL")
                }
                .frame(minHeight: 54)
                ProgressView(value: Double(min(store.waterTotal(on: date), store.waterGoalML)),
                             total: Double(max(store.waterGoalML, 1)))
                    .tint(Theme.accentText)
                    .padding(.bottom, 20)
                }
                NagisenSection("Add water") {
                HStack {
                    TextField("Amount in mL", text: $amount).keyboardType(.numberPad)
                    Button("Add") {
                        if let value = Int(amount) { store.addWater(value, on: date); amount = "" }
                    }
                    .disabled(!(1...5000).contains(Int(amount) ?? 0))
                }
                .frame(minHeight: 54)
                }
                NagisenSection("Daily target") {
                HStack {
                    TextField("Target in mL", text: $goal).keyboardType(.numberPad)
                    Button("Save") {
                        if let value = Int(goal), (250...10000).contains(value) {
                            store.waterGoalML = value
                        }
                    }
                    .disabled(!(250...10000).contains(Int(goal) ?? 0))
                }
                .frame(minHeight: 54)
                Text("Set a target that fits your own needs.")
                    .font(.footnote).foregroundStyle(Theme.muted).padding(.bottom, 14)
                }
                NagisenSection("Reminders") {
                Toggle("Gentle water check-ins", isOn: Binding(
                    get: { remindersEnabled },
                    set: { enabled in
                        if enabled {
                            WaterReminders.enable { allowed in
                                remindersEnabled = allowed
                                reminderError = !allowed
                            }
                        } else {
                            remindersEnabled = false
                            WaterReminders.disable()
                        }
                    }
                ))
                .tint(Theme.accent)
                .frame(minHeight: 54)
                Text("When enabled, NAGISEN sends a check-in every two hours from 9 a.m. to 9 p.m. Turn this off at any time.")
                    .font(.footnote).foregroundStyle(Theme.muted).padding(.bottom, 14)
                }
                NagisenSection("History") {
                let entries = store.waterEntries.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
                    .sorted { $0.date > $1.date }
                if entries.isEmpty {
                    Text("No water logged on this day.").foregroundStyle(Theme.muted)
                } else {
                    ForEach(entries) { entry in
                        HStack {
                            Text(entry.date.formatted(.dateTime.hour().minute()))
                            Spacer()
                            Text("\(entry.milliliters) mL").foregroundStyle(Theme.accentText)
                            Button { store.deleteWater(entry) } label: {
                                Image(systemName: "trash").foregroundStyle(Theme.muted)
                                    .frame(width: 36, height: 44)
                            }
                            .accessibilityLabel("Delete water entry")
                        }
                        .frame(minHeight: 54)
                    }
                }
                }
            }
            .padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(NagisenBackdrop())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { goal = String(store.waterGoalML) }
        .alert("Notifications are off", isPresented: $reminderError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Allow NAGISEN notifications in iPhone Settings to use water check-ins.")
        }
    }
}

enum WaterReminders {
    private static let hours = [9, 11, 13, 15, 17, 19, 21]
    private static let ids = hours.map { "nagisen.water.\($0)" }
    private static let oldIds = hours.map { "daywell.water.\($0)" }

    static func reconcile() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: oldIds + ids)
        center.removeDeliveredNotifications(withIdentifiers: oldIds)
        guard UserDefaults.standard.bool(forKey: "daywell.water.reminders") else { return }
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            schedule()
        }
    }

    static func enable(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                guard granted else { completion(false); return }
                disable()
                schedule()
                completion(true)
            }
        }
    }

    static func disable() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: oldIds + ids)
    }

    private static func schedule() {
        for hour in hours {
            let content = UNMutableNotificationContent()
            content.title = "NAGISEN water check-in"
            content.body = "Take a moment to log any water you have had."
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: hour, minute: 0), repeats: true)
            let request = UNNotificationRequest(identifier: "nagisen.water.\(hour)", content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request)
        }
    }
}

private struct MacroRow: View {
    let name: String
    let amount: Double
    let goal: Int
    let color: Color

    var body: some View {
        let percentage = Int((amount / Double(max(goal, 1)) * 100).rounded())
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(name.uppercased()).font(.caption2.weight(.semibold)).tracking(1)
            }
            .foregroundStyle(color)
            Text("\(Int(amount.rounded()))g")
                .font(.system(.title2, design: .serif))
                .foregroundStyle(color)
            Text("\(percentage)% of \(goal)g").font(.caption).foregroundStyle(Theme.muted)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.line)
                    Capsule().fill(color)
                        .frame(width: geometry.size.width * min(CGFloat(amount) / CGFloat(max(goal, 1)), 1))
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MealCard: View {
    @EnvironmentObject private var store: NutritionStore
    @State private var showingDeleteMeal = false
    let meal: Meal
    let date: Date
    let onAdd: () -> Void

    var body: some View {
        let items = store.entries(on: date, meal: meal)
        let calories = items.reduce(0) { $0 + $1.calories }
        VStack(alignment: .leading, spacing: 17) {
            HStack(spacing: 12) {
                Image(systemName: meal.symbol)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(meal.highlight)
                    .frame(width: 43, height: 43)
                    .background(meal.highlight.opacity(0.14), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 2) {
                    Text(meal.rawValue).font(.system(size: 22, design: .serif))
                    Text(items.isEmpty ? "Ready when you are" : "\(items.count) \(items.count == 1 ? "food" : "foods") logged")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(calories.formatted())
                        .font(.system(size: 22, weight: .medium, design: .rounded))
                        .foregroundStyle(items.isEmpty ? Theme.muted : meal.highlight)
                    Text("kcal").font(.caption2).foregroundStyle(Theme.muted)
                }
                if !items.isEmpty {
                    Button { showingDeleteMeal = true } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Delete all foods from \(meal.rawValue)")
                }
            }
            if items.isEmpty {
                Text("Start with a food or a meal you love.")
                    .font(.subheadline).foregroundStyle(Theme.muted)
                    .padding(.vertical, 8)
            } else {
                Rectangle().fill(Theme.line.opacity(0.7)).frame(height: 1)
                ForEach(items) { item in
                    HStack(alignment: .center, spacing: 11) {
                        RoundedRectangle(cornerRadius: 2).fill(meal.highlight.opacity(0.8))
                            .frame(width: 3, height: 30)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.food.name).font(.subheadline.weight(.medium))
                            Text(item.portionDescription)
                                .font(.caption).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Text("\(item.calories)").font(.subheadline.weight(.medium)).foregroundStyle(Theme.muted)
                        Button(role: .destructive) { store.delete(item) } label: {
                            Image(systemName: "minus.circle")
                                .font(.body).foregroundStyle(Theme.muted)
                                .frame(width: 34, height: 34)
                        }
                        .accessibilityLabel("Delete \(item.food.name)")
                    }
                    .padding(.vertical, 2)
                }
                HStack(spacing: 13) {
                    mealMacro("P", grams: items.reduce(0) { $0 + $1.protein }, color: Theme.protein)
                    mealMacro("C", grams: items.reduce(0) { $0 + $1.carbs }, color: Theme.carbs)
                    mealMacro("F", grams: items.reduce(0) { $0 + $1.fat }, color: Theme.fat)
                }
                .padding(.top, 3)
            }
            Button(action: onAdd) {
                HStack {
                    Image(systemName: "plus.circle.fill").font(.title3)
                    Text("Add to \(meal.rawValue)").font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.caption.weight(.semibold))
                }
                .foregroundStyle(meal.highlight)
                .padding(.horizontal, 14).frame(height: 46)
                .background(meal.highlight.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
            }
            .buttonStyle(.plain)
        }
        .padding(19)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nagisenGlass(in: RoundedRectangle(cornerRadius: 21), tint: meal.highlight.opacity(0.08))
        .confirmationDialog("Clear \(meal.rawValue)?", isPresented: $showingDeleteMeal) {
            Button("Delete whole meal", role: .destructive) { store.deleteMeal(meal, on: date) }
        } message: {
            Text("This removes every food logged for \(meal.rawValue) on this day.")
        }
    }

    private func mealMacro(_ name: String, grams: Double, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text("\(name) \(Int(grams.rounded()))g")
                .font(.caption2.weight(.medium))
                .foregroundStyle(Theme.muted)
        }
    }
}

private struct DiaryView: View {
    @EnvironmentObject private var store: NutritionStore
    @Binding var date: Date
    let onAdd: (Date, Meal) -> Void
    @State private var showingCalendar = false
    @State private var showingQuickAdd = false
    @State private var showingCopyConfirmation = false

    private var previousDay: Date { Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date }

    var body: some View {
        let totals = store.totals(on: date)
        let available = store.goals(on: date).calories
        let bonus = store.weeklyCalorieBonus(on: date)
        let remaining = available - totals.calories
        let overage = CalorieBalanceStyle.overage(totals.calories, goal: available)
        let balanceColor = CalorieBalanceStyle.color(totals.calories, goal: available)
        let overPercent = Int(Double(overage) / Double(max(available, 1)) * 100)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 23) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("YOUR DIARY")
                            .font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(Theme.accentText)
                        Text("A day, one bite at a time")
                            .font(.system(size: 30, design: .serif))
                    }
                    HStack(spacing: 14) {
                        Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                            .accessibilityLabel("Previous day")
                        Spacer()
                        Button { showingCalendar = true } label: {
                            VStack(spacing: 3) {
                                Text(Calendar.current.isDateInToday(date) ? "Today" : date.formatted(.dateTime.month(.abbreviated).day()))
                                    .font(.system(size: 22, design: .serif))
                                Text(date.formatted(.dateTime.weekday(.wide).year()))
                                    .font(.caption).foregroundStyle(Theme.muted)
                            }
                        }
                        Spacer()
                        Button { shift(1) } label: { Image(systemName: "chevron.right") }
                            .disabled(Calendar.current.isDateInToday(date))
                            .accessibilityLabel("Next day")
                    }
                    .padding(14)
                    .nagisenGlass(in: RoundedRectangle(cornerRadius: 16), tint: Theme.surface.opacity(0.18))

                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("EATEN").font(.caption2.weight(.semibold)).tracking(1.4).foregroundStyle(Theme.muted)
                                Text("\(totals.calories)").font(.system(size: 37, design: .serif))
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(overage > 0 ? "OVER GOAL" : "REMAINING")
                                    .font(.caption2.weight(.semibold)).tracking(1.4).foregroundStyle(Theme.muted)
                                Text(abs(remaining).formatted())
                                    .font(.system(size: 37, design: .serif)).foregroundStyle(balanceColor)
                            }
                        }
                        ProgressView(value: Double(min(max(totals.calories, 0), available)),
                                     total: Double(max(available, 1)))
                            .tint(overage > 0 ? balanceColor : Theme.red)
                        if overage > 0 {
                            Text("+\(overage.formatted()) kcal · \(overPercent)% over your target")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(balanceColor)
                        }
                        Text("\(available) kcal goal")
                            .font(.caption).foregroundStyle(Theme.muted)
                        Text("Bonus calories: \(bonus.formatted())")
                            .font(.caption.weight(.medium)).foregroundStyle(Theme.accentText)
                        HStack(spacing: 15) {
                            diaryMacro("Protein", value: totals.protein, color: Theme.protein)
                            diaryMacro("Carbs", value: totals.carbs, color: Theme.carbs)
                            diaryMacro("Fat", value: totals.fat, color: Theme.fat)
                        }
                    }
                    .cardStyle()

                    WaterCard(date: date)

                    VStack(alignment: .leading, spacing: 13) {
                        Text("QUICK ADD")
                            .font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(Theme.muted)
                        HStack(spacing: 8) {
                            ForEach(Meal.allCases) { meal in
                                Button { onAdd(date, meal) } label: {
                                    VStack(spacing: 7) {
                                        Image(systemName: meal.symbol).font(.title3)
                                            .frame(height: 25)
                                        Text(meal.rawValue).font(.caption2.weight(.medium)).lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity).frame(height: 66)
                                    .background(Theme.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                                }
                            }
                        }
                        HStack(spacing: 18) {
                            Button { showingQuickAdd = true } label: {
                                Label("Calories & macros", systemImage: "bolt.fill")
                            }
                            if !store.entries(on: previousDay).isEmpty {
                                Button { showingCopyConfirmation = true } label: {
                                    Label("Copy yesterday", systemImage: "doc.on.doc")
                                }
                            }
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.accentText)
                    }

                    Text("Meals").font(.system(size: 25, design: .serif))
                    ForEach(Meal.allCases) { meal in
                        DiaryMealCard(meal: meal, date: date) { onAdd(date, meal) }
                    }
                }
                .foregroundStyle(Theme.ink)
                .padding(24)
            }
            .background(NagisenBackdrop())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingCalendar) { CalendarLogView(date: $date) }
            #if DEBUG
            .onAppear {
                // Test-only: opens the month view so the marks can be captured.
                if ProcessInfo.processInfo.arguments.contains("-NAGISENOpenCalendar") {
                    showingCalendar = true
                }
            }
            #endif
            .sheet(isPresented: $showingQuickAdd) { NavigationStack { QuickAddView(date: date) } }
            .confirmationDialog("Copy yesterday's food?", isPresented: $showingCopyConfirmation) {
                Button("Add \(store.entries(on: previousDay).count) foods") {
                    store.copyDay(from: previousDay, to: date)
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This adds yesterday's foods to the selected day. You can edit or remove entries afterwards.")
            }
        }
    }

    private func shift(_ days: Int) {
        if let next = Calendar.current.date(byAdding: .day, value: days, to: date) { date = next }
    }

    private func diaryMacro(_ name: String, value: Double, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(name) \(Int(value.rounded()))g")
                .font(.caption2.weight(.medium)).foregroundStyle(Theme.muted)
        }
    }
}

private struct DiaryMealCard: View {
    let meal: Meal
    let date: Date
    let onAdd: () -> Void

    var body: some View {
        MealCard(meal: meal, date: date, onAdd: onAdd)
    }
}

extension View {
    @ViewBuilder
    func softTopScrollEdgeEffect() -> some View {
        if #available(iOS 26.0, *) {
            self.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }

    @ViewBuilder
    func nagisenGlass<S: Shape>(in shape: S, tint: Color = .clear) -> some View {
        if #available(iOS 26.0, *) {
            self
                .glassEffect(.regular.tint(tint), in: shape)
                .overlay(shape.stroke(
                    LinearGradient(colors: [.white.opacity(0.20), .white.opacity(0.04), Theme.accent.opacity(0.12)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 0.5))
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .background(tint, in: shape)
                .overlay(shape.stroke(.white.opacity(0.12), lineWidth: 0.5))
        }
    }

    func cardStyle() -> some View {
        self.padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .nagisenGlass(in: RoundedRectangle(cornerRadius: 20), tint: Theme.surface.opacity(0.20))
    }

    func softCardStyle() -> some View {
        self.padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .nagisenPanel()
    }

    /// The quiet panel behind grouped settings and forms: a breath of ink and a hairline edge,
    /// so the paper shows through instead of a grey glass slab.
    func nagisenPanel(cornerRadius: CGFloat = 22) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background(Theme.ink.opacity(0.035), in: shape)
            .overlay(shape.strokeBorder(Theme.ink.opacity(0.10), lineWidth: 0.5))
    }

    /// Replaces a sheet's system navigation bar with NAGISEN's own: serif title, quiet close mark, one action.
    func nagisenSheetBar(_ title: String, closeSymbol: String = "xmark", onClose: @escaping () -> Void,
                         actionTitle: String? = nil, actionEnabled: Bool = true, busy: Bool = false,
                         onAction: (() -> Void)? = nil) -> some View {
        toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                NagisenSheetBar(title: title, closeSymbol: closeSymbol, onClose: onClose, actionTitle: actionTitle,
                                actionEnabled: actionEnabled, busy: busy, onAction: onAction)
                    .background(Theme.paper)
            }
    }

    func accentCardStyle(_ accent: Color) -> some View {
        self.padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .nagisenGlass(in: RoundedRectangle(cornerRadius: 20), tint: accent.opacity(0.12))
    }
}

struct NagisenHeader: View {
    let title: String
    let subtitle: String?
    let symbol: String
    let onBack: () -> Void
    let actionTitle: String?
    let actionEnabled: Bool
    let onAction: (() -> Void)?

    init(_ title: String, subtitle: String? = nil, symbol: String = "chevron.left",
         onBack: @escaping () -> Void, actionTitle: String? = nil,
         actionEnabled: Bool = true, onAction: (() -> Void)? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.onBack = onBack
        self.actionTitle = actionTitle
        self.actionEnabled = actionEnabled
        self.onAction = onAction
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Button(action: onBack) {
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 38, height: 38, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(symbol == "xmark" ? "Close" : "Back")
                Spacer()
                if let actionTitle, let onAction {
                    Button(actionTitle, action: onAction)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(actionEnabled ? Theme.accentText : Theme.muted)
                        .disabled(!actionEnabled)
                }
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 32, weight: .regular, design: .serif))
                    .foregroundStyle(Theme.ink)
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(.bottom, 8)
    }
}

/// One choice in a NAGISEN action sheet.
struct NagisenAction: Identifiable {
    let id = UUID()
    let title: String
    var symbol: String? = nil
    var destructive = false
    var selected = false
    let run: () -> Void
}

/// NAGISEN's own action menu, opened beside the button that asked for it: paper, hairlines, quiet icons.
struct NagisenActionSheet: View {
    let title: String
    let actions: [NagisenAction]
    let choose: (NagisenAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold)).tracking(2.2)
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .padding(.bottom, 8)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                        if index > 0 {
                            Rectangle().fill(Theme.ink.opacity(0.08)).frame(height: 0.5)
                                .padding(.leading, action.symbol == nil ? 0 : 52)
                        }
                        row(action)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 6)
        .frame(width: 290, height: min(CGFloat(48 + actions.count * 57), 440))
        .presentationCompactAdaptation(.popover)
        .presentationBackground(Theme.surface)
    }

    private func row(_ action: NagisenAction) -> some View {
        let tint = action.destructive ? Theme.danger : Theme.ink
        return Button { choose(action) } label: {
            HStack(spacing: 16) {
                if let symbol = action.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .regular))
                        .frame(width: 32, height: 32)
                        .overlay(Circle().strokeBorder(tint.opacity(0.3), lineWidth: 0.5))
                }
                Text(action.title).font(.body).lineLimit(2)
                Spacer(minLength: 8)
                if action.selected {
                    Image(systemName: "checkmark").font(.footnote.weight(.semibold)).foregroundStyle(Theme.accentText)
                }
            }
            .foregroundStyle(tint)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(action.selected ? .isSelected : [])
    }
}

private struct NagisenActionsModifier: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let actions: () -> [NagisenAction]
    /// Runs after the sheet has gone, so an action can open another sheet or dialog.
    @State private var pending: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .popover(isPresented: $isPresented, arrowEdge: .top) {
                NagisenActionSheet(title: title, actions: actions()) { action in
                    pending = action.run
                    isPresented = false
                }
            }
            .onChange(of: isPresented) { _, open in
                guard !open, let run = pending else { return }
                pending = nil
                // Wait for the popover to leave, so the action can present a dialog or sheet.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { run() }
            }
    }
}

extension View {
    func nagisenActions(isPresented: Binding<Bool>, title: String,
                        actions: @escaping () -> [NagisenAction]) -> some View {
        modifier(NagisenActionsModifier(isPresented: isPresented, title: title, actions: actions))
    }
}

/// A labelled choice that opens the NAGISEN action sheet, in place of a menu-style Picker.
struct NagisenPicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [(value: Value, label: String)]
    @State private var choosing = false

    init(_ title: String, selection: Binding<Value>, options: [(value: Value, label: String)]) {
        self.title = title
        _selection = selection
        self.options = options
    }

    var body: some View {
        Button { choosing = true } label: {
            HStack(spacing: 8) {
                Text(title).foregroundStyle(Theme.ink)
                Spacer(minLength: 8)
                Text(options.first { $0.value == selection }?.label ?? "")
                    .foregroundStyle(Theme.accentText)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.muted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(options.first { $0.value == selection }?.label ?? "")
        .nagisenActions(isPresented: $choosing, title: title) {
            options.map { option in
                NagisenAction(title: option.label, selected: option.value == selection) { selection = option.value }
            }
        }
    }
}

/// A text field on the quiet panel instead of the system's rounded box.
struct NagisenFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.subheadline)
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .nagisenPanel(cornerRadius: 12)
    }
}

extension TextFieldStyle where Self == NagisenFieldStyle {
    static var nagisen: NagisenFieldStyle { NagisenFieldStyle() }
}

/// The top of a sheet. The title sits centered in serif; the close mark and the action stay light.
struct NagisenSheetBar: View {
    let title: String
    var closeSymbol = "xmark"
    let onClose: () -> Void
    var actionTitle: String?
    var actionEnabled = true
    var busy = false
    var onAction: (() -> Void)?

    var body: some View {
        ZStack {
            Text(title)
                .font(.system(size: 18, weight: .regular, design: .serif))
                .lineLimit(1)
                .padding(.horizontal, 96)
            HStack {
                Button(action: onClose) {
                    Image(systemName: closeSymbol)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .overlay(Circle().strokeBorder(Theme.ink.opacity(0.16), lineWidth: 0.5))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(closeSymbol == "xmark" ? "Close" : "Back")
                Spacer()
                if let actionTitle, let onAction {
                    if busy {
                        ProgressView().frame(width: 44, height: 44)
                    } else {
                        Button(action: onAction) {
                            Text(actionTitle)
                                .font(.footnote.weight(.semibold)).tracking(0.4)
                                .foregroundStyle(actionEnabled ? Color.white : Theme.muted)
                                .padding(.horizontal, 16).frame(height: 32)
                                .background(actionEnabled ? Theme.accent : Color.clear, in: Capsule())
                                .overlay(Capsule().strokeBorder(Theme.ink.opacity(actionEnabled ? 0 : 0.16), lineWidth: 0.5))
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .disabled(!actionEnabled)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }
}

struct NagisenPageHeading: View {
    let kicker: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                // One brand color for every section, matching the dot beside NAGISEN on Dashboard.
                Circle().fill(Theme.red).frame(width: 9, height: 9)
                Text(kicker.uppercased())
                    .font(.caption2.weight(.semibold)).tracking(2.5)
                    .foregroundStyle(Theme.muted)
            }
            Text(title)
                .font(.system(size: 34, weight: .regular, design: .serif))
                .foregroundStyle(Theme.ink)
                .minimumScaleFactor(0.8)
                .lineLimit(1)
            Text(subtitle)
                .font(.subheadline).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct NagisenSection<Content: View>: View {
    let title: String
    let content: Content
    var edgeToEdge = false

    init(_ title: String, edgeToEdge: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
        self.edgeToEdge = edgeToEdge
    }

    var body: some View {
        if edgeToEdge {
            VStack(alignment: .leading, spacing: 12) {
                Text(title.uppercased())
                    .font(.caption2.weight(.semibold)).tracking(2.2)
                    .foregroundStyle(Theme.muted)
                VStack(alignment: .leading, spacing: 0) { content }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface.opacity(0.52))
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text(title.uppercased())
                    .font(.caption2.weight(.semibold)).tracking(2.2)
                    .foregroundStyle(Theme.muted)
                    .padding(.leading, 2)
                VStack(alignment: .leading, spacing: 0) { content }
                    .padding(.horizontal, 19)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .nagisenPanel()
            }
        }
    }
}

struct NagisenTextRow: View {
    let title: String
    let placeholder: String
    let unit: String?
    let color: Color?
    @Binding var text: String
    let keyboard: UIKeyboardType

    init(_ title: String, placeholder: String, unit: String? = nil,
         text: Binding<String>, keyboard: UIKeyboardType = .numberPad, color: Color? = nil) {
        self.title = title
        self.placeholder = placeholder
        self.unit = unit
        self._text = text
        self.keyboard = keyboard
        self.color = color
    }

    var body: some View {
        HStack(spacing: 10) {
            if let color { Circle().fill(color).frame(width: 7, height: 7) }
            Text(title).foregroundStyle(color ?? Theme.ink)
            Spacer()
            TextField(placeholder, text: $text)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: 130)
            if let unit { Text(unit).foregroundStyle(Theme.muted) }
        }
        .font(.body)
        .frame(minHeight: 54)
    }
}

struct NagisenPrimaryButton: View {
    let title: String
    let enabled: Bool
    let action: () -> Void

    init(_ title: String, enabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.enabled = enabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .foregroundStyle(.white)
                .background(enabled ? Theme.accent : Theme.muted.opacity(0.45),
                            in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// The logo drawing itself each time the app opens: the horizon spreads, the sun rises behind it,
/// then the name appears and everything fades into the app. Built on Core Animation so it plays
/// in the render server at up to 120 fps, unaffected by launch work on the main thread.
private struct LaunchIntroView: UIViewRepresentable {
    let onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeUIView(context: Context) -> IntroView { IntroView(reduceMotion: reduceMotion, onFinish: onFinish) }
    func updateUIView(_ view: IntroView, context: Context) {}

    final class IntroView: UIView {
        private let reduceMotion: Bool
        private let onFinish: () -> Void
        private var started = false
        private let sunClip = CALayer()
        private let sun = CAShapeLayer()
        private let longLine = CALayer()
        private let shortLine = CALayer()
        private let name = CATextLayer()
        /// The sun's red from the app icon.
        private let sunColor = UIColor(red: 0.70, green: 0.32, blue: 0.25, alpha: 1)

        init(reduceMotion: Bool, onFinish: @escaping () -> Void) {
            self.reduceMotion = reduceMotion
            self.onFinish = onFinish
            super.init(frame: .zero)
            sunClip.masksToBounds = true
            sunClip.addSublayer(sun)
            [sunClip, longLine, shortLine, name].forEach(layer.addSublayer)
            isAccessibilityElement = true
            accessibilityLabel = "NAGISEN"
        }

        required init?(coder: NSCoder) { nil }

        override func layoutSubviews() {
            super.layoutSubviews()
            let ink = UIColor(Theme.ink).resolvedColor(with: traitCollection).cgColor
            backgroundColor = UIColor(Theme.paper).resolvedColor(with: traitCollection)
            let center = CGPoint(x: bounds.midX, y: bounds.midY - 24)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            // Only the part above the horizon shows, so the sun comes up from behind it.
            sunClip.frame = CGRect(x: center.x - 80, y: center.y - 80, width: 160, height: 128)
            sun.path = UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 84, height: 84)).cgPath
            sun.fillColor = sunColor.cgColor
            sun.bounds = CGRect(x: 0, y: 0, width: 84, height: 84)
            sun.position = CGPoint(x: 80, y: 62)
            for (line, width, height, dy) in [(longLine, 128.0, 2.5, 44.5), (shortLine, 76.0, 1.5, 55.5)] {
                line.backgroundColor = ink
                line.bounds = CGRect(x: 0, y: 0, width: width, height: height)
                line.cornerRadius = height / 2
                line.position = CGPoint(x: center.x, y: center.y + dy)
            }
            name.string = NSAttributedString(string: "NAGISEN", attributes: [
                .font: UIFont.systemFont(ofSize: 15, weight: .semibold), .kern: 7,
                .foregroundColor: UIColor(cgColor: ink)])
            name.alignmentMode = .center
            name.contentsScale = traitCollection.displayScale
            name.frame = CGRect(x: 0, y: center.y + 110, width: bounds.width, height: 22)
            CATransaction.commit()
            if !started, bounds.width > 0 {
                started = true
                play()
            }
        }

        private func play() {
            let now = CACurrentMediaTime()
            let fadeAt = reduceMotion ? 1.2 : 2.9
            if !reduceMotion {
                for line in [longLine, shortLine] {
                    line.add(animation("transform.scale.x", from: 0, to: 1, at: now, duration: 0.7), forKey: "spread")
                }
                let rise = CASpringAnimation(keyPath: "position.y")
                rise.fromValue = 62 + 88
                rise.toValue = 62
                rise.stiffness = 90
                rise.damping = 17
                rise.duration = rise.settlingDuration
                sun.add(timed(rise, at: now + 0.35), forKey: "rise")
                name.add(animation("opacity", from: 0, to: 1, at: now + 1.25, duration: 0.6), forKey: "appear")
                name.add(animation("transform.translation.y", from: 6, to: 0, at: now + 1.25, duration: 0.6), forKey: "settle")
            }
            let fade = animation("opacity", from: 1, to: 0, at: now + fadeAt, duration: 0.45, easing: .easeIn)
            fade.isRemovedOnCompletion = false
            layer.add(fade, forKey: "leave")
            DispatchQueue.main.asyncAfter(deadline: .now() + fadeAt + 0.45) { [onFinish] in onFinish() }
        }

        private func animation(_ keyPath: String, from: CGFloat, to: CGFloat, at time: CFTimeInterval,
                               duration: CFTimeInterval, easing: CAMediaTimingFunctionName = .easeOut) -> CABasicAnimation {
            let animation = CABasicAnimation(keyPath: keyPath)
            animation.fromValue = from
            animation.toValue = to
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(name: easing)
            return timed(animation, at: time)
        }

        /// Starts at `time`, holds its first frame until then, and asks for ProMotion's full rate.
        private func timed<T: CAAnimation>(_ animation: T, at time: CFTimeInterval) -> T {
            animation.beginTime = time
            animation.fillMode = .both
            animation.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
            return animation
        }
    }
}
