import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Light adjustments to a photo before it goes under a share card. The photo keeps its full frame:
/// nothing is cropped, turned or filtered. Kept apart from the image so reopening starts from the original.
struct PhotoEdits: Equatable {
    enum Tool: String, CaseIterable, Identifiable {
        case exposure, brightness, contrast, saturation, warmth, sharpness, vignette
        var id: String { rawValue }
        var name: String {
            switch self {
            case .exposure: String(localized: "Exposure")
            case .brightness: String(localized: "Brightness")
            case .contrast: String(localized: "Contrast")
            case .saturation: String(localized: "Saturation")
            case .warmth: String(localized: "Warmth")
            case .sharpness: String(localized: "Sharpness")
            case .vignette: String(localized: "Vignette")
            }
        }
        var symbol: String {
            switch self {
            case .exposure: "plusminus.circle"
            case .brightness: "sun.max"
            case .contrast: "circle.lefthalf.filled"
            case .saturation: "drop"
            case .warmth: "thermometer.sun"
            case .sharpness: "triangle"
            case .vignette: "circle.dashed"
            }
        }
        /// Sharpness and vignette only go up from nothing; the rest go both ways from 0.
        var range: ClosedRange<Double> { self == .sharpness || self == .vignette ? 0...1 : -1...1 }
    }

    var values: [Tool: Double] = [:]

    subscript(tool: Tool) -> Double {
        get { values[tool] ?? 0 }
        set { values[tool] = newValue == 0 ? nil : newValue }
    }
}

enum PhotoEditor {
    private static let context = CIContext()

    /// The photo with its adjustments, same proportions as the original. `maxEdge` keeps previews quick.
    static func apply(_ edits: PhotoEdits, to image: UIImage, maxEdge: CGFloat = 2400) -> UIImage {
        let base = upright(image, maxEdge: maxEdge)
        guard edits != PhotoEdits(), var input = CIImage(image: base) else { return base }
        let extent = input.extent

        let controls = CIFilter.colorControls()
        controls.inputImage = input
        controls.brightness = Float(edits[.brightness] * 0.25)
        controls.contrast = Float(1 + edits[.contrast] * 0.5)
        controls.saturation = Float(1 + edits[.saturation])
        input = controls.outputImage ?? input

        if edits[.exposure] != 0 {
            let exposure = CIFilter.exposureAdjust()
            exposure.inputImage = input
            exposure.ev = Float(edits[.exposure] * 1.5)
            input = exposure.outputImage ?? input
        }
        if edits[.warmth] != 0 {
            let temperature = CIFilter.temperatureAndTint()
            temperature.inputImage = input
            temperature.neutral = CIVector(x: 6500, y: 0)
            temperature.targetNeutral = CIVector(x: 6500 + edits[.warmth] * 2500, y: 0)
            input = temperature.outputImage ?? input
        }
        if edits[.sharpness] > 0 {
            let sharpen = CIFilter.sharpenLuminance()
            sharpen.inputImage = input
            sharpen.sharpness = Float(edits[.sharpness] * 2)
            input = sharpen.outputImage ?? input
        }
        if edits[.vignette] > 0 {
            let vignette = CIFilter.vignette()
            vignette.inputImage = input
            vignette.intensity = Float(edits[.vignette] * 2)
            vignette.radius = Float(max(extent.width, extent.height) / 1.5)
            input = vignette.outputImage ?? input
        }
        // Cut back to the original frame: some filters spill past the edges.
        guard let cgImage = context.createCGImage(input, from: extent) else { return base }
        return UIImage(cgImage: cgImage)
    }

    /// Bakes in the camera's orientation and caps the size, so Core Image sees an upright, light image.
    private static func upright(_ image: UIImage, maxEdge: CGFloat) -> UIImage {
        let scale = min(1, maxEdge / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}

/// Light, exposure and colour for the photo under a share card. The whole photo is always kept.
struct PhotoEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let original: UIImage
    @State var edits: PhotoEdits
    let onDone: (UIImage, PhotoEdits) -> Void

    @State private var tool = PhotoEdits.Tool.exposure
    @State private var preview: UIImage?
    /// A small copy for live previews, so sliders stay smooth.
    @State private var small: UIImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Group {
                    if let preview {
                        Image(uiImage: preview).resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else {
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 24)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(PhotoEdits.Tool.allCases) { item in
                            Button { tool = item } label: {
                                Label(item.name, systemImage: item.symbol)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12).frame(height: 36)
                                    .foregroundStyle(tool == item ? Theme.ink : Theme.muted)
                                    .background(tool == item ? Theme.accent.opacity(0.3) : .clear, in: Capsule())
                                    .overlay(Capsule().strokeBorder(Theme.ink.opacity(edits[item] == 0 ? 0.12 : 0.5), lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                HStack(spacing: 12) {
                    Slider(value: Binding(get: { edits[tool] }, set: { edits[tool] = ($0 * 100).rounded() / 100 }), in: tool.range)
                    Text("\(Int((edits[tool] * 100).rounded()))").font(.caption.monospacedDigit()).frame(width: 36)
                    Button { edits[tool] = 0 } label: { Image(systemName: "arrow.uturn.backward") }
                        .disabled(edits[tool] == 0)
                        .accessibilityLabel(String(localized: "Reset \(tool.name)"))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .padding(.top, 8)
            .foregroundStyle(Theme.ink)
            .tint(Theme.accentText)
            .background(Color(red: 0.035, green: 0.03, blue: 0.035).ignoresSafeArea())
            .nagisenSheetBar(String(localized: "Edit photo"), onClose: { dismiss() }, actionTitle: String(localized: "Done")) {
                onDone(PhotoEditor.apply(edits, to: original), edits)
                dismiss()
            }
            .task {
                small = PhotoEditor.apply(PhotoEdits(), to: original, maxEdge: 1000)
                refresh()
            }
            .onChange(of: edits) { _, _ in refresh() }
        }
    }

    private func refresh() {
        guard let small else { return }
        preview = PhotoEditor.apply(edits, to: small, maxEdge: 1000)
    }
}
