import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Light adjustments to a photo before it goes under a share card. The photo keeps its full frame:
/// nothing is cropped, turned or filtered. Kept apart from the image so reopening starts from the original.
struct PhotoEdits: Equatable {
    enum Tool: String, CaseIterable, Identifiable {
        case exposure, brightness, contrast, structure, warmth, saturation, fade, highlights, shadows, vignette, tiltShift, sharpness
        var id: String { rawValue }
        var name: String {
            switch self {
            case .exposure: String(localized: "Exposure")
            case .brightness: String(localized: "Brightness")
            case .contrast: String(localized: "Contrast")
            case .structure: String(localized: "Structure")
            case .fade: String(localized: "Fade")
            case .highlights: String(localized: "Highlights")
            case .shadows: String(localized: "Shadows")
            case .tiltShift: String(localized: "Tilt shift")
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
            case .structure: "triangle.lefthalf.filled"
            case .fade: "circle.dotted"
            case .highlights: "circle.tophalf.filled"
            case .shadows: "circle.bottomhalf.filled"
            case .tiltShift: "camera.aperture"
            case .saturation: "drop"
            case .warmth: "thermometer.sun"
            case .sharpness: "diamond"
            case .vignette: "circle.dashed"
            }
        }
        /// These only go up from nothing; the rest go both ways from 0.
        var range: ClosedRange<Double> { [.sharpness, .vignette, .structure, .fade, .tiltShift].contains(self) ? 0...1 : -1...1 }
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
        if edits[.highlights] != 0 || edits[.shadows] != 0 || edits[.fade] != 0 {
            // One tone curve: shadows lift the low quarter, highlights the high quarter, fade raises the blacks.
            let (high, low, fade) = (edits[.highlights], edits[.shadows], edits[.fade])
            let level = { (value: Double) in CGFloat(min(max(value, 0), 1)) }
            let curve = CIFilter.toneCurve()
            curve.inputImage = input
            curve.point0 = CGPoint(x: 0, y: level(fade * 0.25))
            curve.point1 = CGPoint(x: 0.25, y: level(0.25 + low * 0.12 + fade * 0.08))
            curve.point2 = CGPoint(x: 0.5, y: level(0.5 + (low + high) * 0.04))
            curve.point3 = CGPoint(x: 0.75, y: level(0.75 + high * 0.12))
            curve.point4 = CGPoint(x: 1, y: level(1 - fade * 0.05))
            input = curve.outputImage ?? input
        }
        if edits[.structure] > 0 {
            // Contrast over a wide radius brings out texture without sharpening edges.
            let structure = CIFilter.unsharpMask()
            structure.inputImage = input
            structure.radius = Float(max(extent.width, extent.height) / 100)
            structure.intensity = Float(edits[.structure] * 1.5)
            input = structure.outputImage ?? input
        }
        if edits[.sharpness] > 0 {
            let sharpen = CIFilter.sharpenLuminance()
            sharpen.inputImage = input
            sharpen.sharpness = Float(edits[.sharpness] * 2)
            input = sharpen.outputImage ?? input
        }
        if edits[.tiltShift] > 0 {
            // Blurs the top and bottom, leaving a sharp band across the middle.
            let blurred = input.clampedToExtent()
                .applyingGaussianBlur(sigma: edits[.tiltShift] * max(extent.width, extent.height) / 120)
                .cropped(to: extent)
            let top = CIFilter.smoothLinearGradient()
            top.point0 = CGPoint(x: 0, y: extent.maxY); top.point1 = CGPoint(x: 0, y: extent.minY + extent.height * 0.62)
            top.color0 = .white; top.color1 = .black
            let bottom = CIFilter.smoothLinearGradient()
            bottom.point0 = CGPoint(x: 0, y: extent.minY); bottom.point1 = CGPoint(x: 0, y: extent.minY + extent.height * 0.38)
            bottom.color0 = .white; bottom.color1 = .black
            if let upper = top.outputImage, let lower = bottom.outputImage {
                let mask = upper.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: lower]).cropped(to: extent)
                input = blurred.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: input, kCIInputMaskImageKey: mask])
            }
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

/// The photo's Edit tab: a row of round tools; each opens its own slider with Cancel and Done.
/// Hold the photo to see the original. The whole photo is always kept.
struct PhotoEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let original: UIImage
    @State var edits: PhotoEdits
    let onDone: (UIImage, PhotoEdits) -> Void

    @State private var tool: PhotoEdits.Tool?
    /// The tool's value when it opened, so Cancel can put it back.
    @State private var before = 0.0
    @State private var preview: UIImage?
    /// A small copy for live previews, so sliders stay smooth.
    @State private var small: UIImage?
    @State private var comparing = false

    var body: some View {
        // The stack keeps the bars clear of the status bar and home indicator inside a full-screen cover.
        NavigationStack { content.toolbar(.hidden, for: .navigationBar) }
    }

    private var content: some View {
        VStack(spacing: 0) {
            HStack {
                Button(String(localized: "Cancel")) { dismiss() }
                Spacer()
                Text(tool?.name ?? String(localized: "Edit")).font(.system(size: 17, design: .serif))
                Spacer()
                Button(String(localized: "Done")) {
                    onDone(PhotoEditor.apply(edits, to: original), edits)
                    dismiss()
                }
                .fontWeight(.semibold)
            }
            .font(.body)
            .opacity(tool == nil ? 1 : 0.0001)
            .overlay { if tool != nil { Text(tool?.name ?? "").font(.system(size: 17, design: .serif)) } }
            .disabled(tool != nil)
            .padding(.horizontal, 20)
            .frame(height: 52)

            ZStack(alignment: .top) {
                if let shown = comparing ? small : preview {
                    Image(uiImage: shown).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    ProgressView()
                }
                if comparing {
                    Text("Original").font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(10)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.12, perform: {}, onPressingChanged: { comparing = $0 })
            .accessibilityHint(String(localized: "Hold to see the original"))

            Group {
                if let tool {
                    VStack(spacing: 14) {
                        Text("\(Int((edits[tool] * 100).rounded()))").font(.system(size: 15, design: .serif).monospacedDigit())
                        Slider(value: Binding(get: { edits[tool] }, set: { edits[tool] = ($0 * 100).rounded() / 100 }), in: tool.range)
                        HStack {
                            Button(String(localized: "Cancel")) { edits[tool] = before; self.tool = nil }
                            Spacer()
                            Button(String(localized: "Done")) { self.tool = nil }.fontWeight(.semibold)
                        }
                        .frame(minHeight: 44)
                    }
                    .padding(.horizontal, 24)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(PhotoEdits.Tool.allCases) { item in
                                Button { before = edits[item]; tool = item } label: {
                                    VStack(spacing: 7) {
                                        Text(item.name).font(.caption2).foregroundStyle(edits[item] == 0 ? Theme.muted : Theme.ink)
                                        Image(systemName: item.symbol)
                                            .font(.system(size: 22, weight: .light))
                                            .frame(width: 62, height: 62)
                                            .overlay(Circle().strokeBorder(Theme.ink.opacity(edits[item] == 0 ? 0.22 : 0.7), lineWidth: 1))
                                        Circle().fill(Theme.accentText).frame(width: 4, height: 4).opacity(edits[item] == 0 ? 0 : 1)
                                    }
                                    .frame(width: 72)
                                }
                                .buttonStyle(.plain)
                                .accessibilityValue(edits[item] == 0 ? "" : "\(Int((edits[item] * 100).rounded()))")
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
            .frame(height: 150)
        }
        .foregroundStyle(Theme.ink)
        .tint(Theme.accentText)
        .background(Color(red: 0.035, green: 0.03, blue: 0.035).ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .task {
            small = PhotoEditor.apply(PhotoEdits(), to: original, maxEdge: 1000)
            refresh()
        }
        .onChange(of: edits) { _, _ in refresh() }
    }

    private func refresh() {
        guard let small else { return }
        preview = PhotoEditor.apply(edits, to: small, maxEdge: 1000)
    }
}
