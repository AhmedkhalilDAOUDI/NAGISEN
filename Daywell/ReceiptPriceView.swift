import SwiftUI
import PhotosUI
import Vision
import UIKit

/// Turns a photo of a grocery receipt into prices for the foods it lists.
///
/// Nothing is written without being shown first: the receipt text is read on the device, each row
/// is matched to a food the person already eats, and the price that would be stored is displayed
/// before it can be saved.
struct ReceiptPriceView: View {
    @EnvironmentObject private var store: NutritionStore
    @Environment(\.dismiss) private var dismiss

    @State private var photoItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var isReading = false
    @State private var status: String?
    @State private var rows: [DraftRow] = []

    struct DraftRow: Identifiable {
        let id = UUID()
        let line: ReceiptLine
        var food: Food?
        var price: FoodPrice?
        var include: Bool
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    picker
                    if isReading {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Reading the receipt on this iPhone…")
                                .font(.subheadline).foregroundStyle(Theme.muted)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .nagisenGlass(in: RoundedRectangle(cornerRadius: 18))
                    }
                    if let status {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                            .padding(.horizontal, 4)
                    }
                    if !rows.isEmpty { review }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            .background(Theme.surface.ignoresSafeArea())
            .navigationTitle("Receipt prices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(rows.filter { $0.include && $0.food != nil && $0.price != nil }.isEmpty)
                }
            }
            .sheet(isPresented: $showingCamera) {
                ReceiptCamera { image in
                    showingCamera = false
                    if let image { read(image) }
                }
                .ignoresSafeArea()
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        read(image)
                    }
                    photoItem = nil
                }
            }
        }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Photograph a receipt")
                .font(.system(size: 19, design: .serif))
                .foregroundStyle(Theme.ink)
            Text("Every row becomes a price for the food you already log. Nothing is saved until you confirm it.")
                .font(.caption).foregroundStyle(Theme.muted)

            HStack(spacing: 10) {
                Button {
                    showingCamera = true
                } label: {
                    Label("Camera", systemImage: "camera.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Theme.accentText, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(Theme.surface)
                }
                .buttonStyle(.plain)

                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Library", systemImage: "photo.on.rectangle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Theme.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(Theme.ink)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nagisenGlass(in: RoundedRectangle(cornerRadius: 20))
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Read from the receipt")
                    .font(.system(size: 19, design: .serif))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("\(rows.filter(\.include).count) of \(rows.count)")
                    .font(.caption).foregroundStyle(Theme.muted)
            }

            ForEach($rows) { $row in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.line.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Spacer()
                        Text(FoodCost.display(row.line.total))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.muted)
                        Toggle("", isOn: $row.include)
                            .labelsHidden()
                            .tint(Theme.red)
                    }

                    HStack(spacing: 8) {
                        Menu {
                            ForEach(candidates(for: row.line), id: \.id) { candidate in
                                Button(candidate.name) {
                                    row.food = candidate
                                    row.price = ReceiptMatcher.price(for: row.line, food: candidate)
                                }
                            }
                            Button("Not a food I track") { row.food = nil; row.price = nil }
                        } label: {
                            HStack(spacing: 4) {
                                Text(row.food?.name ?? "Choose food")
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Theme.surface.opacity(0.7), in: Capsule())
                            .foregroundStyle(Theme.ink)
                        }

                        Spacer()

                        Text(priceText(row))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(row.price == nil ? Theme.muted : Theme.accentText)
                    }
                }
                .padding(12)
                .background(Theme.surface.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nagisenGlass(in: RoundedRectangle(cornerRadius: 20))
    }

    private func priceText(_ row: DraftRow) -> String {
        guard let price = row.price, !price.isEmpty else { return "no price yet" }
        if let per100g = price.per100g { return FoodCost.display(per100g) + " / 100 g" }
        if let perServing = price.perServing { return FoodCost.display(perServing) + " / serving" }
        return "no price yet"
    }

    /// Foods worth matching against: what has actually been eaten recently, plus anything custom.
    private func candidateFoods() -> [Food] {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -120, to: Date()) ?? Date()
        var seen: Set<String> = []
        var foods: [Food] = []
        for entry in store.entries.sorted(by: { $0.date > $1.date }) where entry.date >= cutoff {
            let key = FoodCost.key(for: entry.food)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            foods.append(entry.food)
        }
        for food in store.customFoods {
            let key = FoodCost.key(for: food)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            foods.append(food)
        }
        return foods
    }

    private func candidates(for line: ReceiptLine) -> [Food] {
        let foods = candidateFoods()
        let scored = ReceiptMatcher.candidates(for: line, in: foods)
        return scored.isEmpty ? foods.prefix(12).map { $0 } : scored.map(\.food)
    }

    private func read(_ image: UIImage) {
        isReading = true
        status = nil
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            isReading = false
            status = "That photo could not be read."
            return
        }
        Task {
            let lines = await Task.detached(priority: .userInitiated) { () -> [String] in
                let text = VNRecognizeTextRequest()
                text.recognitionLevel = .accurate
                text.usesLanguageCorrection = true
                do {
                    try VNImageRequestHandler(data: data, options: [:]).perform([text])
                } catch {
                    return []
                }
                let fragments = (text.results ?? []).compactMap { observation -> ReceiptRows.Fragment? in
                    guard let string = observation.topCandidates(1).first?.string else { return nil }
                    return ReceiptRows.Fragment(text: string,
                                                x: Double(observation.boundingBox.minX),
                                                y: Double(observation.boundingBox.midY))
                }
                return ReceiptRows.join(fragments)
            }.value

            let parsed = ReceiptParser.parse(lines)
            let foods = candidateFoods()
            rows = parsed.map { line in
                let matches = ReceiptMatcher.candidates(for: line, in: foods)
                let best = matches.first
                return DraftRow(line: line,
                                food: best?.food,
                                price: best.flatMap { ReceiptMatcher.price(for: line, food: $0.food) },
                                include: best != nil)
            }
            isReading = false
            if parsed.isEmpty {
                status = "No priced rows were found. Try a flatter photo with the whole receipt in frame."
            } else if rows.filter(\.include).isEmpty {
                status = "Read \(parsed.count) rows, but none matched a food you log. Choose the food for each row below."
            } else {
                status = "Read \(parsed.count) rows. Check the matches before saving."
            }
        }
    }

    private func save() {
        for row in rows where row.include {
            guard let food = row.food, let price = row.price, !price.isEmpty else { continue }
            store.setPrice(price, for: food)
        }
        dismiss()
    }
}

/// Minimal camera sheet: a receipt is a physical thing, so the camera has to be one tap away.
struct ReceiptCamera: UIViewControllerRepresentable {
    let onImage: (UIImage?) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: ReceiptCamera

        init(_ parent: ReceiptCamera) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.onImage(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onImage(nil)
        }
    }
}
