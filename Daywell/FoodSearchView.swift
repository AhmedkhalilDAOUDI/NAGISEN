import SwiftUI
import PhotosUI
import Vision
import Speech
import AVFoundation

private enum FoodBrowseMode: String, CaseIterable, Identifiable {
    case search = "Search"
    case myFoods = "My Foods"
    case recipes = "Recipes"
    case meals = "Meals"
    var id: String { rawValue }
}

struct FoodSearchView: View {
    @EnvironmentObject private var store: NutritionStore
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @FocusState private var searchFocused: Bool
    @State private var mode = FoodBrowseMode.search
    @State private var selectedFood: Food?
    @State private var showingCreate = false
    @State private var showingRecipeEditor = false
    @State private var showingScanner = false
    @State private var pendingFood: Food?
    @State private var onlineFoods: [Food] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var photoHint: String?
    @State private var addedFoodMessage: String?
    @State private var toastTask: Task<Void, Never>?
    @StateObject private var voice = FoodVoiceSearch()
    let date: Date
    let initialMeal: Meal

    @AppStorage(QuickPicks.storageKey) private var hiddenPicks = Data()

    private var localMatches: [Food] {
        guard !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return store.myFoods }
        return store.myFoods.filter {
            $0.name.localizedCaseInsensitiveContains(search) || $0.brand.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            NagisenHeader("Add food", subtitle: "Find it, then log it.", symbol: "xmark", onBack: { dismiss() })
                .padding(.horizontal, 24).padding(.top, 10)
            Picker("Food list", selection: $mode) {
                ForEach(FoodBrowseMode.allCases) { tab in Text(tab.rawValue).tag(tab) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            if mode == .search {
            HStack(spacing: 9) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                    TextField("Food or brand", text: $search)
                        .focused($searchFocused)
                        .submitLabel(.search)
                        .onSubmit(searchOnline)
                        .onChange(of: search) { _, _ in
                            onlineFoods = []
                            searchError = nil
                        }
                }
                .padding(12)
                .nagisenGlass(in: RoundedRectangle(cornerRadius: 12), tint: Theme.surface.opacity(0.18))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
                Button(action: searchOnline) {
                    Image(systemName: "arrow.right")
                        .font(.body.weight(.semibold))
                        .frame(width: 43, height: 43)
                        .nagisenGlass(in: RoundedRectangle(cornerRadius: 12), tint: Theme.surface.opacity(0.18))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
                }
                .disabled(search.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 || isSearching)
                .accessibilityLabel("Search online")
                Button { showingScanner = true } label: {
                    Image(systemName: "barcode.viewfinder")
                        .font(.title3)
                        .frame(width: 43, height: 43)
                        .nagisenGlass(in: RoundedRectangle(cornerRadius: 12), tint: Theme.surface.opacity(0.18))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
                }
                .accessibilityLabel("Scan barcode")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            HStack(spacing: 20) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Use photo", systemImage: "photo")
                        .font(.caption.weight(.medium))
                }
                .accessibilityLabel("Suggest food from photo")
                Button {
                    if voice.isRecording {
                        voice.stop()
                        search = voice.transcript
                        searchOnline()
                    } else { voice.start() }
                } label: {
                    Label(voice.isRecording ? "Stop voice search" : "Use voice",
                          systemImage: voice.isRecording ? "stop.fill" : "mic")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(voice.isRecording ? Theme.accentText : Theme.ink)
                }
                .accessibilityLabel(voice.isRecording ? "Stop voice search" : "Search food by voice")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            if let photoHint {
                Text(photoHint)
                    .font(.caption).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18).padding(.bottom, 8)
            }
            if voice.isRecording || voice.status != nil {
                Text(voice.isRecording ? "Listening… tap stop to search. \(voice.transcript)" : (voice.status ?? ""))
                    .font(.caption).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18).padding(.bottom, 8)
            }
            }

            List {
                if mode == .search { searchSections }
                if mode == .myFoods { myFoodSections }
                if mode == .recipes { recipeSections }
                if mode == .meals { previousMealSections }
                Section {
                    Button { showingCreate = true } label: {
                        Label("Create a custom food", systemImage: "plus")
                            .fontWeight(.medium)
                    }
                    .listRowBackground(Theme.surface.opacity(0.4))
                    if mode == .recipes {
                        Button { showingRecipeEditor = true } label: {
                            Label("Create a recipe", systemImage: "book.closed")
                                .fontWeight(.medium)
                        }
                        .listRowBackground(Theme.surface.opacity(0.4))
                    }
                } footer: {
                    Text("Online data: Open Food Facts (ODbL). Check product labels before logging.")
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .scrollDismissesKeyboard(.interactively)
        }
        .background(NagisenBackdrop())
        .overlay(alignment: .bottom) {
            if let addedFoodMessage {
                Label(addedFoodMessage, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 17)
                    .padding(.vertical, 13)
                    .nagisenGlass(in: Capsule(), tint: Theme.protein.opacity(0.22))
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 5)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .tint(Theme.accentText)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { searchFocused = false }
                    .fontWeight(.semibold)
            }
        }
        .onChange(of: mode) { _, _ in searchFocused = false }
        .navigationDestination(item: $selectedFood) { food in
            LogFoodView(food: food, date: date, initialMeal: initialMeal) { meal in
                selectedFood = nil
                showAddedFood(food.name, in: meal)
            }
        }
        .sheet(isPresented: $showingCreate, onDismiss: showPendingFood) {
            NavigationStack {
                CreateFoodView { food in
                    store.customFoods.insert(food, at: 0)
                    pendingFood = food
                    showingCreate = false
                }
            }
        }
        .sheet(isPresented: $showingRecipeEditor) {
            NavigationStack { CreateRecipeView() }
        }
        .sheet(isPresented: $showingScanner, onDismiss: showPendingFood) {
            NavigationStack {
                BarcodeScannerView { food in
                    pendingFood = food
                    showingScanner = false
                }
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await suggestFromPhoto(item) }
        }
        .onDisappear {
            voice.stop()
            toastTask?.cancel()
        }
    }

    @ViewBuilder private var searchSections: some View {
        if search.isEmpty {
            let usual = store.frequentFoods(excluding: QuickPicks.hidden(in: hiddenPicks))
            if usual.isEmpty {
                Section {
                    Text("The foods you log most will appear here. Search above, scan a barcode or add one manually.")
                        .foregroundStyle(Theme.muted)
                }
            } else {
                Section("Your usual foods") {
                    ForEach(usual) { food in foodRow(food) }
                }
            }
        } else {
            if !localMatches.isEmpty {
                Section("On this device") {
                    ForEach(localMatches) { food in foodRow(food) }
                }
            }
            if isSearching {
                Section { SwiftUI.ProgressView("Searching Open Food Facts…") }
            }
            if !onlineFoods.isEmpty {
                Section("Open Food Facts") {
                    ForEach(onlineFoods) { food in foodRow(food) }
                }
            }
            if let searchError {
                Section { Text(searchError).font(.footnote).foregroundStyle(Theme.accentText) }
            }
            if localMatches.isEmpty && onlineFoods.isEmpty && !isSearching && searchError == nil {
                Section { Text("Tap the arrow to search online.").foregroundStyle(Theme.muted) }
            }
        }
    }

    @ViewBuilder private var myFoodSections: some View {
        if !store.customFoods.isEmpty {
            Section("Created by you") {
                ForEach(store.customFoods) { food in foodRow(food) }
            }
        }
        let createdKeys = Set(store.customFoods.map { FoodCost.key(for: $0) })
        let recent = Array(store.recentFoods()
            .filter { !createdKeys.contains(FoodCost.key(for: $0)) }
            .prefix(30))
        if !recent.isEmpty {
            Section("Previously logged") {
                ForEach(recent) { food in foodRow(food) }
            }
        }
        if store.customFoods.isEmpty && recent.isEmpty {
            Section { Text("Foods you create or log will appear here.").foregroundStyle(Theme.muted) }
        }
    }

    @ViewBuilder private var recipeSections: some View {
        if store.savedRecipes.isEmpty {
            Section { Text("Recipes you build will appear here.").foregroundStyle(Theme.muted) }
        } else {
            Section("Your recipes") {
                ForEach(store.savedRecipes) { recipe in
                    foodRow(recipe.asFood)
                }
                .onDelete { offsets in store.savedRecipes.remove(atOffsets: offsets) }
            }
        }
    }

    @ViewBuilder private var previousMealSections: some View {
        let meals = Array(store.loggedMeals.prefix(20))
        if meals.isEmpty {
            Section { Text("Your previous meals will appear here.").foregroundStyle(Theme.muted) }
        } else {
            Section("Previous meals") {
                ForEach(meals) { meal in
                    NavigationLink {
                        RepeatMealView(previous: meal, date: date, initialMeal: initialMeal)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(meal.meal.rawValue).foregroundStyle(Theme.ink)
                                Text("\(meal.date.formatted(date: .abbreviated, time: .omitted)) · \(meal.entries.count) foods")
                                    .font(.caption).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Text("\(meal.calories) kcal").font(.subheadline).foregroundStyle(Theme.muted)
                        }
                    }
                    .listRowBackground(Theme.surface.opacity(0.4))
                }
            }
        }
    }

    private func foodRow(_ food: Food) -> some View {
        HStack(spacing: 8) {
            NavigationLink {
                LogFoodView(food: food, date: date, initialMeal: initialMeal) { meal in
                    showAddedFood(food.name, in: meal)
                }
            } label: {
                HStack(spacing: 11) {
                    Image(systemName: food.source == nil ? "leaf" : "barcode")
                        .foregroundStyle(Theme.accentText).frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(food.name).fontWeight(.medium).foregroundStyle(Theme.ink)
                        Text([food.brand, food.serving].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Text("\(food.calories) kcal").font(.subheadline).foregroundStyle(Theme.muted)
                }
                .contentShape(Rectangle())
            }
            if food.source != "Open Food Facts" {
                Button {
                    store.add(food, to: initialMeal, servings: 1, on: date)
                    showAddedFood(food.name)
                } label: {
                    Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(Theme.accentText)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Quick log one serving of \(food.name)")
            }
        }
        .listRowBackground(Theme.surface.opacity(0.4))
    }

    private func showPendingFood() {
        selectedFood = pendingFood
        pendingFood = nil
    }

    private func showAddedFood(_ name: String, in meal: Meal? = nil) {
        searchFocused = false
        toastTask?.cancel()
        withAnimation(.easeInOut(duration: 0.22)) {
            addedFoodMessage = "Added \(name) to \((meal ?? initialMeal).rawValue)"
        }
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.22)) { addedFoodMessage = nil }
        }
    }

    private func searchOnline() {
        searchFocused = false
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2, !isSearching else { return }
        isSearching = true
        searchError = nil
        Task {
            do {
                let foods = try await OpenFoodFactsService().search(query)
                guard search.trimmingCharacters(in: .whitespacesAndNewlines) == query else {
                    isSearching = false
                    return
                }
                onlineFoods = foods
                if foods.isEmpty {
                    searchError = "No online foods with usable nutrition data. Try another term or create a food."
                }
            } catch {
                searchError = error.localizedDescription
            }
            isSearching = false
        }
    }

    private func suggestFromPhoto(_ item: PhotosPickerItem) async {
        photoHint = "Looking at your photo…"
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data)?.cgImage else {
            photoHint = "Couldn’t read that photo. Try searching by name."
            return
        }
        let request = VNClassifyImageRequest()
        do {
            try VNImageRequestHandler(cgImage: image).perform([request])
            let candidate = (request.results ?? []).first {
                $0.confidence >= 0.12 && !$0.identifier.lowercased().contains("non-food")
            }
            guard let candidate else {
                photoHint = "No clear food suggestion. Search by name or use the barcode."
                return
            }
            let suggestion = candidate.identifier.components(separatedBy: ",").first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? candidate.identifier
            search = suggestion
            photoHint = "Photo suggests “\(suggestion)”. Check the result and serving before logging."
            searchOnline()
        } catch {
            photoHint = "No clear food suggestion. Search by name or use the barcode."
        }
    }
}

@MainActor
private final class FoodVoiceSearch: ObservableObject {
    @Published var isRecording = false
    @Published var transcript = ""
    @Published var status: String?
    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale.current)
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var tapInstalled = false

    func start() {
        SFSpeechRecognizer.requestAuthorization { [weak self] authorization in
            DispatchQueue.main.async {
                guard let self else { return }
                guard authorization == .authorized else {
                    self.status = "Allow Speech Recognition in iPhone Settings to use voice search."
                    return
                }
                self.beginRecording()
            }
        }
    }

    private func beginRecording() {
        guard !isRecording, let recognizer, recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else {
            status = "On-device voice search is unavailable. Use the keyboard microphone instead."
            return
        }
        do {
            status = nil
            transcript = ""
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers])
            try session.setActive(true)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = true
            self.request = request
            let input = engine.inputNode
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
                request.append(buffer)
            }
            tapInstalled = true
            engine.prepare()
            try engine.start()
            isRecording = true
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                DispatchQueue.main.async {
                    if let result { self?.transcript = result.bestTranscription.formattedString }
                    if error != nil { self?.stop() }
                }
            }
        } catch {
            stop()
            status = "Couldn’t start voice search. Check microphone access."
        }
    }

    func stop() {
        if engine.isRunning { engine.stop() }
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

struct QuickAddView: View {
    @EnvironmentObject private var store: NutritionStore
    @Environment(\.dismiss) private var dismiss
    let date: Date
    @State private var name = "Quick add"
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var meal = Meal.snacks

    private func value(_ text: String) -> Double? {
        guard let number = Double(text.replacingOccurrences(of: ",", with: ".")),
              number.isFinite, (0...10_000).contains(number) else { return nil }
        return number
    }

    private var canSave: Bool {
        value(calories) != nil && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (protein.isEmpty || value(protein) != nil) &&
        (carbs.isEmpty || value(carbs) != nil) &&
        (fat.isEmpty || value(fat) != nil)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                NagisenHeader("Quick add", subtitle: "When you know the numbers.", symbol: "xmark") { dismiss() }
                NagisenSection("Entry") {
                    TextField("Name", text: $name).frame(minHeight: 52)
                    Divider()
                    NagisenPicker("Meal", selection: $meal, options: Meal.allCases.map { ($0, $0.rawValue) })
                        .frame(minHeight: 52)
                    Divider()
                    LabeledContent("Date", value: date.formatted(date: .abbreviated, time: .omitted))
                        .frame(minHeight: 52)
                }
                NagisenSection("Nutrition") {
                    NagisenTextRow("Calories", placeholder: "Required", unit: "kcal", text: $calories, keyboard: .decimalPad)
                    Divider()
                    NagisenTextRow("Protein", placeholder: "Optional", unit: "g", text: $protein, keyboard: .decimalPad, color: Theme.protein)
                    Divider()
                    NagisenTextRow("Carbs", placeholder: "Optional", unit: "g", text: $carbs, keyboard: .decimalPad, color: Theme.carbs)
                    Divider()
                    NagisenTextRow("Fat", placeholder: "Optional", unit: "g", text: $fat, keyboard: .decimalPad, color: Theme.fat)
                }
                NagisenPrimaryButton("Add to diary", enabled: canSave) {
                    guard let energy = value(calories) else { return }
                    let food = Food(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                    serving: "1 entry", calories: Int(energy.rounded()),
                                    protein: value(protein) ?? 0, carbs: value(carbs) ?? 0,
                                    fat: value(fat) ?? 0, source: "Your estimate",
                                    missingMacros: [("protein", protein), ("carbs", carbs), ("fat", fat)]
                                        .compactMap { $0.1.isEmpty ? $0.0 : nil })
                    store.add(food, to: meal, servings: 1, on: date)
                    dismiss()
                }
            }
            .padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(NagisenBackdrop())
        .tint(Theme.accentText)
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct RepeatMealView: View {
    @EnvironmentObject private var store: NutritionStore
    @Environment(\.dismiss) private var dismiss
    let previous: LoggedMeal
    let date: Date
    @State private var meal: Meal
    init(previous: LoggedMeal, date: Date, initialMeal: Meal) {
        self.previous = previous
        self.date = date
        self._meal = State(initialValue: initialMeal)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                NagisenHeader("Repeat meal", subtitle: "Bring a familiar meal forward.", symbol: "xmark", onBack: { dismiss() })
                NagisenSection("Log to") {
                NagisenPicker("Meal", selection: $meal, options: Meal.allCases.map { ($0, $0.rawValue) })
                .frame(minHeight: 54)
                Divider()
                LabeledContent("Date", value: date.formatted(date: .abbreviated, time: .omitted))
                    .frame(minHeight: 54)
                }
                NagisenSection("Foods in this meal") {
                ForEach(previous.entries) { entry in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(entry.food.name)
                            Text(entry.portionDescription).font(.caption).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Text("\(entry.calories) kcal").foregroundStyle(Theme.muted)
                    }
                    .frame(minHeight: 62)
                    if entry.id != previous.entries.last?.id { Divider() }
                }
                }
                NagisenPrimaryButton("Add \(previous.entries.count) foods") {
                    for entry in previous.entries {
                        store.add(entry.food, to: meal, servings: entry.servings, on: date,
                                  quantity: entry.loggedQuantity, unit: entry.loggedUnit)
                    }
                    dismiss()
                }
            }
            .padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 32)
        }
        .background(NagisenBackdrop())
        .tint(Theme.accentText)
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct CreateRecipeView: View {
    @EnvironmentObject private var store: NutritionStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var portions = "2"
    @State private var query = ""
    @State private var ingredients: [RecipeIngredient] = []

    private var matchingFoods: [Food] {
        let candidates = store.allFoods + store.recentFoods()
        var seen = Set<String>()
        return candidates.filter { food in
            let key = "\(food.name.lowercased())|\(food.brand.lowercased())|\(food.serving.lowercased())"
            return seen.insert(key).inserted &&
                (query.isEmpty || food.name.localizedCaseInsensitiveContains(query) ||
                 food.brand.localizedCaseInsensitiveContains(query))
        }.prefix(12).map { $0 }
    }

    private var valid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (1...100).contains(Int(portions) ?? 0) && !ingredients.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                NagisenHeader("New recipe", subtitle: "Save what you cook, one portion at a time.", symbol: "xmark", onBack: { dismiss() })
                NagisenSection("Recipe") {
                    TextField("Recipe name", text: $name).frame(minHeight: 54)
                    Divider()
                    NagisenTextRow("Portions", placeholder: "2", text: $portions)
                }
                if !ingredients.isEmpty {
                    NagisenSection("Ingredients") {
                        ForEach($ingredients) { $ingredient in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(ingredient.food.name).font(.subheadline.weight(.medium))
                                    Spacer()
                                    Button { ingredients.removeAll { $0.id == ingredient.id } } label: {
                                        Image(systemName: "xmark").font(.caption).foregroundStyle(Theme.muted)
                                    }
                                    .accessibilityLabel("Remove \(ingredient.food.name)")
                                }
                                Stepper("\(ingredient.servings.formatted(.number.precision(.fractionLength(1)))) × \(ingredient.food.serving)",
                                        value: $ingredient.servings, in: 0.5...20, step: 0.5)
                                    .font(.caption).foregroundStyle(Theme.muted)
                            }
                            .padding(.vertical, 11)
                            if ingredient.id != ingredients.last?.id { Divider() }
                        }
                    }
                }
                NagisenSection("Add ingredients") {
                    TextField("Search your foods", text: $query).frame(minHeight: 54)
                    Divider()
                    ForEach(matchingFoods) { food in
                        Button { ingredients.append(RecipeIngredient(food: food, servings: 1)) } label: {
                            HStack {
                                Text(food.name).foregroundStyle(Theme.ink)
                                Spacer()
                                Text(food.serving).font(.caption).foregroundStyle(Theme.muted)
                                Image(systemName: "plus").foregroundStyle(Theme.accentText)
                            }
                            .frame(minHeight: 50)
                        }
                        .buttonStyle(.plain)
                        if food.id != matchingFoods.last?.id { Divider() }
                    }
                }
                if valid, let count = Int(portions) {
                    let preview = SavedRecipe(name: name, portions: count, ingredients: ingredients).asFood
                    Text("About \(preview.calories) kcal per portion · P \(Int(preview.protein)) g · C \(Int(preview.carbs)) g · F \(Int(preview.fat)) g")
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
                NagisenPrimaryButton("Save recipe", enabled: valid) {
                    guard let count = Int(portions), valid else { return }
                    store.savedRecipes.insert(SavedRecipe(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                                          portions: count, ingredients: ingredients), at: 0)
                    dismiss()
                }
            }
            .padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(NagisenBackdrop())
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// Foods removed from Lab's quick picks and the usual-foods list. Only hides them there;
/// nothing logged is deleted.
enum QuickPicks {
    static let storageKey = "nagisen.quickPicks.hidden"

    static func hidden(in data: Data) -> Set<String> {
        (try? JSONDecoder().decode(Set<String>.self, from: data)) ?? []
    }

    static func encode(_ keys: Set<String>) -> Data {
        (try? JSONEncoder().encode(keys)) ?? Data()
    }
}
