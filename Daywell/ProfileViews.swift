import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ProfileView: View {
    @EnvironmentObject private var store: NutritionStore
    @EnvironmentObject private var community: CommunityCloud
    @EnvironmentObject private var feed: FeedService
    @Environment(\.dismiss) private var dismiss
    @State private var showingSignIn = false
    @State private var exportFile: DataExportFile?
    @State private var showingImporter = false
    @State private var pendingRestore: Data?
    @State private var restoreError = false
    @State private var showingAutomaticRestore = false
    @State private var showingLoseItImport = false
    @State private var showingCloudChoice = false

    private var path: PathProgress {
        PathProgress(store: store)
    }

    @ViewBuilder
    private var accountCard: some View {
        switch feed.state {
        case .notConfigured:
            EmptyView()
        case .signedOut, .needsUsername:
            Button { showingSignIn = true } label: {
                HStack(spacing: 16) {
                    AvatarView(url: nil, username: "N", tier: path.tier, size: 58)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(feed.state == .signedOut ? "Join the community" : "Choose a username")
                            .font(.system(size: 21, design: .serif))
                        Text("Share moments and wear the border you earn.")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .softCardStyle()
            .sheet(isPresented: $showingSignIn) { FeedAccountView() }
        case .ready:
            NavigationLink {
                AccountSettingsView()
            } label: {
                HStack(spacing: 16) {
                    AvatarView(url: feed.avatarURL(feed.avatarPath), username: feed.username ?? "",
                               tier: feed.borderTier, size: 58)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("@\(feed.username ?? "")").font(.system(size: 21, design: .serif))
                        Text(feed.bio.isEmpty ? "Add a photo and a line about you" : feed.bio)
                            .font(.caption).foregroundStyle(Theme.muted).lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .softCardStyle()
        }
    }

    private var pathCard: some View {
        let progress = path
        return NavigationLink {
            PathView(progress: progress)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("PATH").font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(Theme.muted)
                    Spacer()
                    Text(progress.tier.name).font(.caption.weight(.semibold)).foregroundStyle(Theme.accentText)
                }
                ProgressView(value: progress.fractionToNext).tint(Theme.accent)
                Text(progress.pointsToNext.map { "\(progress.points) points · \($0) to \(progress.tier.next?.name ?? "")" }
                     ?? "\(progress.points) points · every border earned")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .softCardStyle()
    }

    private var latestWeight: WeightEntry? {
        store.weights.max { $0.date < $1.date }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    NagisenHeader("Settings", subtitle: "Your account and your app.", symbol: "xmark", onBack: { dismiss() })
                    if store.storageRecoveryNeeded {
                        Text("NAGISEN could not read part of your local history. Restore a recent backup below before logging new data.")
                            .font(.subheadline.weight(.medium)).foregroundStyle(Theme.accentText)
                    }
                    accountCard
                    pathCard

                    VStack(spacing: 0) {
                        NavigationLink {
                            ProgressViewScreen()
                        } label: {
                            MenuRow(symbol: "target", title: "Goals",
                                    detail: "Daily targets, insights & progress")
                        }
                        Divider().overlay(Theme.line)
                        NavigationLink {
                            DietPlanView()
                        } label: {
                            MenuRow(symbol: "fork.knife", title: "Food plan",
                                    detail: "Meals, calories & macros")
                        }
                        Divider().overlay(Theme.line)
                        NavigationLink {
                            WeightHistoryView()
                        } label: {
                            MenuRow(symbol: "scalemass", title: "Weight log",
                                    detail: latestWeight.map { "\($0.kilograms.formatted(.number.precision(.fractionLength(1)))) kg latest" } ?? "Add your first weight")
                        }
                        Divider().overlay(Theme.line)
                        NavigationLink {
                            BodyDetailsView()
                        } label: {
                            MenuRow(symbol: "figure.stand", title: "Body details",
                                    detail: "Age, height & target weight")
                        }
                        Divider().overlay(Theme.line)
                        NavigationLink {
                            AccessoriesView()
                        } label: {
                            MenuRow(symbol: "airpodspro", title: "Accessories",
                                    detail: "AirPods heart rate & Health sources")
                        }
                    }
                    .softCardStyle()

                    VStack(alignment: .leading, spacing: 12) {
                        Label("iCloud sync", systemImage: "icloud")
                            .font(.system(size: 21, design: .serif))
                        Text(community.accountMessage)
                            .font(.subheadline).foregroundStyle(Theme.muted)
                        Text(community.syncMessage)
                            .font(.subheadline).foregroundStyle(Theme.muted)
                        HStack(spacing: 22) {
                            Button("Sync now") { Task { await community.sync(store) } }
                            if community.hasConflict {
                                Button("Choose a copy") { showingCloudChoice = true }
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accentText)
                        .disabled(!community.accountReady || community.isBusy)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .softCardStyle()

                    Button(action: exportData) {
                        MenuRow(symbol: "square.and.arrow.up", title: "Export my data",
                                detail: "Save a copy of your NAGISEN history")
                    }
                    .buttonStyle(.plain)
                    .softCardStyle()
                    Button { showingImporter = true } label: {
                        MenuRow(symbol: "square.and.arrow.down", title: "Restore a backup",
                                detail: "Replace this device's NAGISEN history")
                    }
                    .buttonStyle(.plain)
                    .softCardStyle()
                    Button { showingLoseItImport = true } label: {
                        MenuRow(symbol: "arrow.down.doc",
                                title: "Import from Lose It!",
                                detail: store.legacyStreak.map {
                                    "\($0.count.formatted(.number.grouping(.automatic)))-day streak on file"
                                } ?? "Bring over food history and your streak")
                    }
                    .buttonStyle(.plain)
                    .softCardStyle()
                    if store.latestAutomaticBackup != nil {
                        Button { showingAutomaticRestore = true } label: {
                            MenuRow(symbol: "clock.arrow.circlepath", title: "Recover recent history",
                                    detail: "Restore the latest local backup")
                        }
                        .buttonStyle(.plain)
                        .softCardStyle()
                    }

                    Text("Your history stays on this iPhone and in your private iCloud backup when connected. Feed posts are public. Online food search uses Open Food Facts.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
                .foregroundStyle(Theme.ink)
                .padding(24)
            }
            .background(NagisenBackdrop())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $exportFile) { file in
                DataShareSheet(url: file.url)
            }
            .sheet(isPresented: $showingLoseItImport) {
                LoseItImportView()
                    .environmentObject(store)
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
                guard case .success(let url) = result else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                pendingRestore = try? Data(contentsOf: url)
                restoreError = pendingRestore == nil
            }
            .confirmationDialog("Replace your current NAGISEN history?", isPresented: Binding(
                get: { pendingRestore != nil },
                set: { if !$0 { pendingRestore = nil } }
            )) {
                Button("Replace with backup", role: .destructive) {
                    if let pendingRestore, !store.restoreJSON(pendingRestore) { restoreError = true }
                    pendingRestore = nil
                }
                Button("Cancel", role: .cancel) { pendingRestore = nil }
            } message: {
                Text("This replaces current food, goals, weight, water, and workout history. Export a copy first if you want to keep it.")
            }
            .confirmationDialog("Restore the latest automatic backup?", isPresented: $showingAutomaticRestore) {
                Button("Restore recent history", role: .destructive) {
                    if !store.restoreLatestAutomaticBackup() { restoreError = true }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Current NAGISEN history will be replaced. Export it first if you want to keep both versions.")
            }
            .alert("Could not restore backup", isPresented: $restoreError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Choose a NAGISEN JSON backup created by Export my data.")
            }
            .confirmationDialog("Which history should NAGISEN keep?", isPresented: $showingCloudChoice) {
                Button("Keep this iPhone") { Task { await community.keepThisPhone(store) } }
                Button("Use iCloud copy") { Task { await community.useICloud(store) } }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Both versions changed. The replaced iPhone history is saved to a local backup first.")
            }
            .task { await community.connect(); await community.sync(store) }
        }
    }

    private func exportData() {
        guard let data = store.exportJSON() else { return }
        let name = "NAGISEN-backup-\(Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash))).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        guard (try? data.write(to: url, options: .atomic)) != nil else { return }
        exportFile = DataExportFile(url: url)
    }
}

private struct DataExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

private struct DataShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}

private struct MenuRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: symbol)
                .font(.title3.weight(.light))
                .foregroundStyle(Theme.accentText)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body.weight(.medium)).foregroundStyle(Theme.ink)
                Text(detail).font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

private struct BodyDetailsView: View {
    @EnvironmentObject private var store: NutritionStore
    @Environment(\.dismiss) private var dismiss
    @State private var age = ""
    @State private var height = ""
    @State private var targetWeight = ""

    private func optionalDouble(_ text: String, range: ClosedRange<Double>) -> Double? {
        guard !text.isEmpty, let value = Double(text.replacingOccurrences(of: ",", with: ".")),
              value.isFinite, range.contains(value) else { return nil }
        return value
    }

    private var valid: Bool {
        (age.isEmpty || (Int(age).map { (1...120).contains($0) } ?? false)) &&
        (height.isEmpty || optionalDouble(height, range: 50...250) != nil) &&
        (targetWeight.isEmpty || optionalDouble(targetWeight, range: 20...500) != nil)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                NagisenHeader("Body details", subtitle: "The basics behind your plan.", onBack: { dismiss() },
                              actionTitle: "Save", actionEnabled: valid, onAction: save)
                NagisenSection("About you") {
                    NagisenTextRow("Age", placeholder: "Years", text: $age)
                    Divider().overlay(Theme.line)
                    NagisenTextRow("Height", placeholder: "0", unit: "cm", text: $height, keyboard: .decimalPad)
                }
                NagisenSection("Weight goal") {
                    NagisenTextRow("Target", placeholder: "0", unit: "kg", text: $targetWeight, keyboard: .decimalPad)
                }
                Text("NAGISEN uses these details to estimate your food plan for adults 18 and older.")
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(NagisenBackdrop())
        .tint(Theme.accentText)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            age = store.profile.age.map(String.init) ?? ""
            height = store.profile.heightCm.map { $0.formatted() } ?? ""
            targetWeight = store.profile.targetWeightKg.map { $0.formatted() } ?? ""
        }
    }

    private func save() {
        guard valid else { return }
        store.profile = PersonalProfile(age: Int(age),
            heightCm: optionalDouble(height, range: 50...250),
            targetWeightKg: optionalDouble(targetWeight, range: 20...500))
        dismiss()
    }
}

struct WeightHistoryView: View {
    @EnvironmentObject private var store: NutritionStore
    @Environment(\.dismiss) private var dismiss
    @State private var showingAdd = false

    private var sorted: [WeightEntry] {
        store.weights.sorted { $0.date > $1.date }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                NagisenHeader("Weight log", subtitle: "A clear view of your progress.", onBack: { dismiss() },
                              actionTitle: "Add", onAction: { showingAdd = true })
                if let latest = sorted.first {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("LATEST WEIGHT")
                            .font(.caption2.weight(.semibold)).tracking(2)
                            .foregroundStyle(Theme.muted)
                        Text("\(latest.kilograms.formatted(.number.precision(.fractionLength(1)))) kg")
                            .font(.system(size: 37, weight: .regular, design: .serif))
                            .foregroundStyle(Theme.ink)
                        if let target = store.profile.targetWeightKg {
                            Text("Target: \(target.formatted(.number.precision(.fractionLength(1)))) kg")
                                .font(.subheadline).foregroundStyle(Theme.muted)
                        }
                    }
                    .softCardStyle()
                } else {
                    Text("No weights logged yet")
                        .foregroundStyle(Theme.muted)
                }
                NagisenSection("History") {
                    if sorted.isEmpty {
                        Text("Your entries will appear here.")
                            .foregroundStyle(Theme.muted).frame(minHeight: 54)
                    } else {
                        ForEach(sorted) { entry in
                            HStack {
                                Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                                Spacer()
                                Text("\(entry.kilograms.formatted(.number.precision(.fractionLength(1)))) kg")
                                    .foregroundStyle(Theme.muted)
                                Button { store.weights.removeAll { $0.id == entry.id } } label: {
                                    Image(systemName: "trash").foregroundStyle(Theme.muted)
                                        .frame(width: 36, height: 44)
                                }
                                .accessibilityLabel("Delete weight entry")
                            }
                            .frame(minHeight: 54)
                            if entry.id != sorted.last?.id { Divider() }
                        }
                    }
                }
            }
            .padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 32)
        }
        .background(NagisenBackdrop())
        .tint(Theme.accentText)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingAdd) {
            NavigationStack { AddWeightView() }
        }
    }
}

struct AddWeightView: View {
    @EnvironmentObject private var store: NutritionStore
    @Environment(\.dismiss) private var dismiss
    @State private var kilograms = ""
    @State private var date = Date.now

    private var value: Double? {
        guard let value = Double(kilograms.replacingOccurrences(of: ",", with: ".")),
              value.isFinite, (20...500).contains(value) else { return nil }
        return value
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                NagisenHeader("Log weight", subtitle: "One entry at a time.", symbol: "xmark", onBack: { dismiss() })
                NagisenSection("Weight") {
                    NagisenTextRow("Weight", placeholder: "0.0", unit: "kg", text: $kilograms, keyboard: .decimalPad)
                    Divider().overlay(Theme.line)
                    DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                        .frame(minHeight: 54)
                }
                NagisenPrimaryButton("Save weight", enabled: value != nil) {
                    guard let value else { return }
                    store.weights.append(WeightEntry(date: date, kilograms: value))
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
