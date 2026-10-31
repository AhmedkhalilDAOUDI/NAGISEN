import SwiftUI
import UniformTypeIdentifiers

/// Import from Lose It! — a review-first migration: nothing is written until the user
/// confirms the preview, and the legacy achievement can be carried over on its own when the
/// food export is incomplete or unavailable.
struct LoseItImportView: View {
    @EnvironmentObject private var store: NutritionStore
    @Environment(\.dismiss) private var dismiss

    @State private var showingImporter = false
    @State private var preview: LoseItImportPreview?
    @State private var parseError: String?
    @State private var showingConfirmation = false
    @State private var outcome: NutritionStore.LoseItImportOutcome?
    @State private var isWorking = false

    @State private var legacyCountText = ""
    @State private var legacyEndDate = Calendar.current.startOfDay(for: .now)
    @State private var includeLegacy = false
    @State private var loadedFileNames: [String] = []

    private var existingLegacy: LegacyStreak? { store.legacyStreak }

    private var manualLegacy: LegacyStreak? {
        guard includeLegacy, let count = Int(legacyCountText.replacingOccurrences(of: ",", with: "")),
              count > 0, count < 100_000 else { return nil }
        return LegacyStreak(source: "Lose It!", count: count,
                            lastConfirmedDayKey: StreakEngine.dayKey(for: legacyEndDate),
                            timeZoneIdentifier: TimeZone.current.identifier)
    }

    /// The exact plan that will be committed.
    private var combinedPreview: LoseItImportPreview? {
        var plan = preview ?? LoseItImportPreview()
        if let manualLegacy {
            plan.legacy = StreakEngine.merge(plan.legacy, with: manualLegacy) ?? manualLegacy
        }
        if plan.isEmpty { return nil }
        return plan
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                NagisenHeader("Import from Lose It!", subtitle: "Bring your history over, keep your streak.",
                              symbol: "xmark", onBack: { dismiss() })

                legacyCard

                NagisenSection("Lose It! export") {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Choose the archive Lose It! emailed you (a .zip), or any CSV/JSON file inside it. NAGISEN reads it on this device and never uploads it.")
                            .font(.footnote).foregroundStyle(Theme.muted)
                        Button { showingImporter = true } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "doc.badge.plus").font(.subheadline.weight(.semibold))
                                Text(loadedFileNames.isEmpty ? "Choose files" : "Choose different files")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                            }
                            .foregroundStyle(Theme.accentText)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if !loadedFileNames.isEmpty {
                            Text(loadedFileNames.joined(separator: " · "))
                                .font(.caption).foregroundStyle(Theme.muted)
                        }
                        if let parseError {
                            Text(parseError).font(.caption).foregroundStyle(Theme.red)
                        }
                    }
                }

                if let summary = previewSummary {
                    NagisenSection("Preview") { summary }
                }

                Button(action: { showingConfirmation = true }) {
                    HStack {
                        Spacer()
                        Text(isWorking ? "Importing…" : "Import into NAGISEN")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                    }
                    .padding(.vertical, 15)
                    .foregroundStyle(combinedPreview == nil ? Theme.muted : Color.white)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(combinedPreview == nil ? Theme.line.opacity(0.6) : Theme.accent)
                    )
                }
                .buttonStyle(.plain)
                .disabled(combinedPreview == nil || isWorking)

                Text("A timestamped backup is written before anything changes. Existing diary entries, goals and profile settings are never replaced, and repeating the same import adds nothing.")
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 36)
            .foregroundStyle(Theme.ink)
        }
        .background(NagisenBackdrop())
        .toolbar(.hidden, for: .navigationBar)
        .fileImporter(isPresented: $showingImporter,
                      allowedContentTypes: importTypes,
                      allowsMultipleSelection: true) { result in
            handleFileResult(result)
        }
        .nagisenDialog("Import this data?", isPresented: $showingConfirmation, message: confirmationMessage) {
            [NagisenAction(title: "Import", destructive: true) { commit() }]
        }
        .nagisenDialog("Lose It! import", isPresented: Binding(get: { outcome != nil }, set: { if !$0 { finishImport() } }),
                       message: outcome?.message, cancelTitle: "OK")
        .onAppear(perform: primeFields)
    }

    /// Closing the result: a finished import leaves the screen; an error stays to be fixed.
    private func finishImport() {
        if case .imported = outcome { dismiss() }
        outcome = nil
    }

    // MARK: - Legacy card

    private var legacyCard: some View {
        NagisenSection("Your streak") {
            VStack(alignment: .leading, spacing: 16) {
                if let existingLegacy {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(existingLegacy.count.formatted(.number.grouping(.automatic)))-day streak")
                            .font(.system(size: 30, weight: .regular, design: .serif))
                            .foregroundStyle(Theme.ink)
                        Text("Confirmed \(confirmedDateText(existingLegacy))")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                    Divider().overlay(Theme.line)
                }

                Toggle(isOn: $includeLegacy) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(existingLegacy == nil ? "Carry over a confirmed streak" : "Update the confirmed streak")
                            .font(.subheadline.weight(.medium))
                        Text("Only the achievement is recorded — no invented food entries.")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                }
                .tint(Theme.accentText)

                if includeLegacy {
                    HStack {
                        Text("Consecutive days").font(.subheadline)
                        Spacer()
                        TextField("1,563", text: $legacyCountText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .font(.body.weight(.semibold))
                            .frame(width: 110)
                    }
                    .padding(.vertical, 6)
                    DatePicker("Last confirmed", selection: $legacyEndDate,
                               in: ...Date.now, displayedComponents: .date)
                        .font(.subheadline)
                    if let manualLegacy, StreakEngine.isValidDayKey(manualLegacy.lastConfirmedDayKey) {
                        Text("\(manualLegacy.count.formatted())-day streak · continued from \(manualLegacy.source)")
                            .font(.caption).foregroundStyle(Theme.accentText)
                    } else {
                        Text("Enter the number of consecutive days you confirmed in Lose It!.")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                }
            }
            .padding(.vertical, 16)
        }
    }

    // MARK: - Preview

    private var previewSummary: AnyView? {
        guard let plan = preview, !plan.isEmpty else { return nil }
        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                summaryRow("Food entries", plan.entries.count.formatted())
                summaryRow("Weigh-ins", plan.weights.count.formatted())
                if !plan.dailySummaries.isEmpty {
                    summaryRow("Daily summaries", "\(plan.dailySummaries.count.formatted()) kept for reference")
                }
                if let range = plan.dateRangeText { summaryRow("Date range", range) }
                if plan.duplicateEntries > 0 {
                    summaryRow("Already present", "\(plan.duplicateEntries.formatted()) skipped")
                }
                ForEach(plan.skipped) { skip in
                    VStack(alignment: .leading, spacing: 2) {
                        summaryRow(skip.category, "\(skip.rowCount.formatted()) skipped")
                        Text(skip.reason).font(.caption2).foregroundStyle(Theme.muted)
                    }
                }
                ForEach(plan.warnings, id: \.self) { warning in
                    Text(warning).font(.caption2).foregroundStyle(Theme.accentText)
                }
                if !plan.sourceFiles.isEmpty {
                    Text(plan.sourceFiles.joined(separator: " · "))
                        .font(.caption2).foregroundStyle(Theme.muted).lineLimit(3)
                }
            }
            .padding(.vertical, 16)
        )
    }

    private func summaryRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.subheadline).foregroundStyle(Theme.ink)
            Spacer()
            Text(value).font(.subheadline.weight(.medium)).foregroundStyle(Theme.muted)
        }
    }

    // MARK: - Actions

    private var importTypes: [UTType] {
        var types: [UTType] = [.json, .commaSeparatedText, .tabSeparatedText, .zip, .plainText, .text]
        if let fallback = UTType(filenameExtension: "tsv") { types.append(fallback) }
        if let fallback = UTType(filenameExtension: "csv") { types.append(fallback) }
        return types
    }

    private func primeFields() {
        if let legacy = existingLegacy {
            legacyCountText = String(legacy.count)
            legacyEndDate = StreakEngine.date(fromDayKey: legacy.lastConfirmedDayKey) ?? .now
        } else {
            includeLegacy = true
        }
    }

    private func confirmedDateText(_ legacy: LegacyStreak) -> String {
        guard let date = StreakEngine.date(fromDayKey: legacy.lastConfirmedDayKey) else { return legacy.lastConfirmedDayKey }
        return date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    private var confirmationMessage: String {
        guard let plan = combinedPreview else { return "" }
        var parts: [String] = []
        if !plan.entries.isEmpty { parts.append("\(plan.entries.count) food entries") }
        if !plan.weights.isEmpty { parts.append("\(plan.weights.count) weigh-ins") }
        if let legacy = plan.legacy { parts.append("a \(legacy.count.formatted())-day legacy streak") }
        return "Adds " + parts.joined(separator: ", ") + ". Your current diary and settings stay intact."
    }

    private func handleFileResult(_ result: Result<[URL], Error>) {
        parseError = nil
        switch result {
        case .failure:
            parseError = "The file could not be opened."
        case .success(let urls):
            var files: [LoseItSourceFile] = []
            for url in urls {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else {
                    parseError = "Could not read \(url.lastPathComponent)."
                    continue
                }
                files.append(LoseItSourceFile(name: url.lastPathComponent, data: data))
            }
            guard !files.isEmpty else { return }
            isWorking = true
            let plan = LoseItImporter.preview(files: files,
                                              existingEntryFingerprints: store.entryFingerprints,
                                              existingWeights: store.weights)
            isWorking = false
            preview = plan
            loadedFileNames = files.map(\.name)
            if let legacy = plan.legacy, existingLegacy == nil {
                legacyCountText = String(legacy.count)
                legacyEndDate = StreakEngine.date(fromDayKey: legacy.lastConfirmedDayKey) ?? .now
                includeLegacy = true
            }
            if plan.isEmpty {
                parseError = "No food entries, weigh-ins or streak were found in that file."
            }
        }
    }

    private func commit() {
        guard let plan = combinedPreview else { return }
        isWorking = true
        let result = store.importLoseIt(plan)
        isWorking = false
        outcome = result
    }
}

extension NutritionStore.LoseItImportOutcome: Identifiable {
    var id: String { message }
}
