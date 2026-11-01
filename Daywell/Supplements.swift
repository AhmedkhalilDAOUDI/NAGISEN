import SwiftUI

/// A supplement someone can check off each day. Doses are the usual label amounts, shown as a hint only.
struct Supplement: Identifiable, Hashable {
    let id: String
    let name: String
    let dose: String

    static let creatineID = "creatine"
    private static let customPrefix = "custom:"

    static let catalog: [Supplement] = [
        Supplement(id: creatineID, name: String(localized: "Creatine"), dose: "5 g"),
        Supplement(id: "protein", name: String(localized: "Protein powder"), dose: String(localized: "1 scoop")),
        Supplement(id: "vitaminD", name: String(localized: "Vitamin D3"), dose: "1000–2000 IU"),
        Supplement(id: "omega3", name: String(localized: "Omega-3 (fish oil)"), dose: "1–2 g"),
        Supplement(id: "magnesium", name: String(localized: "Magnesium"), dose: "200–400 mg"),
        Supplement(id: "multivitamin", name: String(localized: "Multivitamin"), dose: String(localized: "1 tablet")),
        Supplement(id: "zinc", name: String(localized: "Zinc"), dose: "10–25 mg"),
        Supplement(id: "iron", name: String(localized: "Iron"), dose: "14–18 mg"),
        Supplement(id: "b12", name: String(localized: "Vitamin B12"), dose: "250–1000 µg"),
        Supplement(id: "vitaminC", name: String(localized: "Vitamin C"), dose: "250–1000 mg"),
        Supplement(id: "calcium", name: String(localized: "Calcium"), dose: "500 mg"),
        Supplement(id: "vitaminK2", name: String(localized: "Vitamin K2"), dose: "100 µg"),
        Supplement(id: "folate", name: String(localized: "Folic acid"), dose: "400 µg"),
        Supplement(id: "iodine", name: String(localized: "Iodine"), dose: "150 µg"),
        Supplement(id: "electrolytes", name: String(localized: "Electrolytes"), dose: String(localized: "1 serving")),
        Supplement(id: "collagen", name: String(localized: "Collagen"), dose: "10 g"),
        Supplement(id: "betaAlanine", name: String(localized: "Beta-alanine"), dose: "3–5 g"),
        Supplement(id: "citrulline", name: String(localized: "Citrulline"), dose: "6–8 g"),
        Supplement(id: "fiber", name: String(localized: "Fiber (psyllium)"), dose: "5–10 g"),
        Supplement(id: "probiotic", name: String(localized: "Probiotic"), dose: String(localized: "1 capsule")),
        Supplement(id: "ashwagandha", name: String(localized: "Ashwagandha"), dose: "300–600 mg"),
        Supplement(id: "melatonin", name: String(localized: "Melatonin"), dose: "0.5–3 mg"),
    ]

    /// Resolves a stored id, including ones the person typed themselves.
    static func find(_ id: String) -> Supplement? {
        if id.hasPrefix(customPrefix) { return Supplement(id: id, name: String(id.dropFirst(customPrefix.count)), dose: "") }
        return catalog.first { $0.id == id }
    }

    static func customID(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : customPrefix + trimmed.prefix(40)
    }

    /// The list before anyone has picked: creatine for people who already tracked it.
    static func startingList(tracksCreatine: Bool) -> [String] {
        tracksCreatine || UserDefaults.standard.object(forKey: OnboardingPlan.tracksCreatineKey) as? Bool == true
            ? [creatineID] : []
    }
}

/// The Dashboard card: one row per chosen supplement, checked off for the shown day.
struct SupplementsCard: View {
    @EnvironmentObject private var store: NutritionStore
    let date: Date
    @State private var choosing = false

    private var chosen: [Supplement] { store.supplements.compactMap(Supplement.find) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SUPPLEMENTS")
                    .font(.caption2.weight(.semibold)).nagisenTracking(1.6)
                    .foregroundStyle(Theme.muted)
                Spacer()
                Button(chosen.isEmpty ? String(localized: "Choose") : String(localized: "Edit")) { choosing = true }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accentText)
                    .frame(minHeight: 44)
            }
            if chosen.isEmpty {
                Text("Pick what you take, then check it off each day.")
                    .font(.subheadline).foregroundStyle(Theme.muted)
            }
            ForEach(chosen) { supplement in
                let taken = store.supplementTaken(supplement.id, on: date)
                Button {
                    store.setSupplementTaken(supplement.id, !taken, on: date)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: taken ? "checkmark.circle.fill" : "circle.dotted")
                            .font(.title3)
                            .foregroundStyle(Theme.accentText)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(supplement.name).font(.system(.body, design: .serif))
                            if !supplement.dose.isEmpty {
                                Text(supplement.dose).font(.caption).foregroundStyle(Theme.muted)
                            }
                        }
                        Spacer()
                    }
                    .foregroundStyle(Theme.ink)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(supplement.name)
                .accessibilityValue(taken ? String(localized: "Taken on this day") : String(localized: "Not taken on this day"))
                .accessibilityAddTraits(taken ? .isSelected : [])
            }
        }
        .softCardStyle()
        .sheet(isPresented: $choosing) { SupplementPicker() }
    }
}

private struct SupplementPicker: View {
    @EnvironmentObject private var store: NutritionStore
    @Environment(\.dismiss) private var dismiss
    @State private var customName = ""

    private var customs: [Supplement] {
        store.supplements.filter { $0.hasPrefix("custom:") }.compactMap(Supplement.find)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Choose what you take. Doses are common label amounts, not advice; follow your own label or your doctor.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                    VStack(spacing: 0) {
                        ForEach(Array((Supplement.catalog + customs).enumerated()), id: \.element.id) { index, supplement in
                            if index > 0 { Divider().overlay(Theme.ink.opacity(0.08)) }
                            row(supplement)
                        }
                    }
                    .padding(.horizontal, 18)
                    .nagisenPanel()
                    HStack {
                        TextField("Add your own", text: $customName)
                            .submitLabel(.done)
                            .onSubmit(addCustom)
                        Button("Add", action: addCustom)
                            .disabled(Supplement.customID(customName) == nil)
                            .foregroundStyle(Theme.accentText)
                    }
                    .frame(minHeight: 54)
                    .padding(.horizontal, 18)
                    .nagisenPanel()
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 32)
            }
            .background(NagisenBackdrop())
            .nagisenSheetBar(String(localized: "Supplements"), onClose: { dismiss() })
        }
    }

    private func row(_ supplement: Supplement) -> some View {
        let picked = store.supplements.contains(supplement.id)
        return Button {
            if picked { store.supplements.removeAll { $0 == supplement.id } } else { store.supplements.append(supplement.id) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(supplement.name).font(.body)
                    if !supplement.dose.isEmpty {
                        Text(supplement.dose).font(.caption).foregroundStyle(Theme.muted)
                    }
                }
                Spacer()
                Image(systemName: picked ? "checkmark" : "plus")
                    .foregroundStyle(picked ? Theme.accentText : Theme.muted)
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }

    private func addCustom() {
        guard let id = Supplement.customID(customName) else { return }
        if !store.supplements.contains(id) { store.supplements.append(id) }
        customName = ""
    }
}
