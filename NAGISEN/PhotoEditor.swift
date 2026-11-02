import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Everything done to a photo before it goes under a share card. Kept separate from the image,
/// so reopening the editor starts from the original with the same choices.
struct PhotoEdits: Equatable {
    enum Filter: String, CaseIterable, Identifiable {
        case original, nagisen, noir, mono, fade, chrome, instant, warm, cool
        var id: String { rawValue }
        var name: String {
            switch self {
            case .original: String(localized: "Original")
            case .nagisen: "NAGISEN"
            case .noir: String(localized: "Noir")
            case .mono: String(localized: "Mono")
            case .fade: String(localized: "Fade")
            case .chrome: String(localized: "Chrome")
            case .instant: String(localized: "Instant")
            case .warm: String(localized: "Warm")
            case .cool: String(localized: "Cool")
            }
        }
    }

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

    var filter = Filter.original
    var values: [Tool: Double] = [:]
    var quarterTurns = 0
    var flipped = false
    /// 1 fills the card; more zooms in.
    var zoom: Double = 1
    /// Where the photo sits in the card, as a fraction of the card size.
    var offset = CGSize.zero

    subscript(tool: Tool) -> Double {
        get { values[tool] ?? 0 }
        set { values[tool] = newValue == 0 ? nil : newValue }
    }
}

enum PhotoEditor {
    static let cardSize = CGSize(width: 1080, height: 1350)
    private static let context = CIContext()

    /// Applies rotation, flip, filter and adjustments. `maxEdge` keeps previews quick.
    static func apply(_ edits: PhotoEdits, to image: UIImage, maxEdge: CGFloat = 2400) -> UIImage {
        guard var input = CIImage(image: upright(image, maxEdge: maxEdge)) else { return image }
        for _ in 0..<((edits.quarterTurns % 4 + 4) % 4) { input = input.oriented(.right) }
        if edits.flipped { input = input.oriented(.upMirrored) }
        input = filtered(input, edits.filter)

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
            vignette.radius = Float(max(input.extent.width, input.extent.height) / 1.5)
            input = vignette.outputImage ?? input
        }
        let extent = input.extent.integral
        guard let cgImage = context.createCGImage(input, from: extent) else { return image }
        return UIImage(cgImage: cgImage)
    }

    /// The edited photo cut to the card: filled, then zoomed and moved as chosen.
    static func render(_ edits: PhotoEdits, from image: UIImage) -> UIImage {
        let edited = apply(edits, to: image)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: cardSize, format: format).image { _ in
            edited.draw(in: frame(for: edited.size, in: cardSize, edits: edits))
        }
    }

    /// Where the photo is drawn inside a card of `card` size.
    static func frame(for size: CGSize, in card: CGSize, edits: PhotoEdits) -> CGRect {
        let fill = max(card.width / max(size.width, 1), card.height / max(size.height, 1)) * max(edits.zoom, 1)
        let drawn = CGSize(width: size.width * fill, height: size.height * fill)
        // Never let the photo slide far enough to show an empty edge.
        let maxX = (drawn.width - card.width) / 2, maxY = (drawn.height - card.height) / 2
        let x = min(max(edits.offset.width * card.width, -maxX), maxX)
        let y = min(max(edits.offset.height * card.height, -maxY), maxY)
        return CGRect(x: (card.width - drawn.width) / 2 + x, y: (card.height - drawn.height) / 2 + y,
                      width: drawn.width, height: drawn.height)
    }

    private static func filtered(_ input: CIImage, _ filter: PhotoEdits.Filter) -> CIImage {
        let effect: CIFilter?
        switch filter {
        case .original: return input
        case .noir: effect = CIFilter.photoEffectNoir()
        case .mono: effect = CIFilter.photoEffectMono()
        case .fade: effect = CIFilter.photoEffectFade()
        case .chrome: effect = CIFilter.photoEffectChrome()
        case .instant: effect = CIFilter.photoEffectInstant()
        case .warm, .cool:
            let temperature = CIFilter.temperatureAndTint()
            temperature.inputImage = input
            temperature.neutral = CIVector(x: 6500, y: 0)
            temperature.targetNeutral = CIVector(x: filter == .warm ? 8200 : 4800, y: 0)
            return temperature.outputImage ?? input
        case .nagisen:
            // The app's grade: shadows into deep burgundy-black, highlights into cream, colour gone.
            let duotone = CIFilter.falseColor()
            duotone.inputImage = input
            duotone.color0 = CIColor(red: 0.07, green: 0.02, blue: 0.045)
            duotone.color1 = CIColor(red: 0.93, green: 0.90, blue: 0.85)
            let controls = CIFilter.colorControls()
            controls.inputImage = duotone.outputImage
            controls.contrast = 1.12
            return controls.outputImage ?? input
        }
        effect?.setValue(input, forKey: kCIInputImageKey)
        return effect?.outputImage ?? input
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

/// Crop, filters and adjustments for the photo under a share card.
struct PhotoEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let original: UIImage
    @State var edits: PhotoEdits
    let onDone: (UIImage, PhotoEdits) -> Void

    private enum Mode: String, CaseIterable { case crop, filters, adjust }
    @State private var mode = Mode.filters
    @State private var tool = PhotoEdits.Tool.exposure
    @State private var preview: UIImage?
    @State private var thumbnails: [PhotoEdits.Filter: UIImage] = [:]
    @State private var dragStart: CGSize?
    @State private var zoomStart: Double?

    /// A small copy for live previews, so sliders stay smooth.
    @State private var small: UIImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                GeometryReader { geometry in
                    let card = CGSize(width: geometry.size.width, height: geometry.size.width * 1.25)
                    ZStack {
                        if let preview {
                            Image(uiImage: preview).resizable()
                                .frame(width: PhotoEditor.frame(for: preview.size, in: card, edits: edits).width,
                                       height: PhotoEditor.frame(for: preview.size, in: card, edits: edits).height)
                                .position(x: PhotoEditor.frame(for: preview.size, in: card, edits: edits).midX,
                                          y: PhotoEditor.frame(for: preview.size, in: card, edits: edits).midY)
                        } else {
                            ProgressView()
                        }
                    }
                    .frame(width: card.width, height: card.height)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.ink.opacity(0.15), lineWidth: 0.5))
                    .contentShape(Rectangle())
                    .gesture(DragGesture()
                        .onChanged { value in
                            let start = dragStart ?? edits.offset
                            dragStart = start
                            edits.offset = CGSize(width: start.width + value.translation.width / card.width,
                                                  height: start.height + value.translation.height / card.height)
                        }
                        .onEnded { _ in dragStart = nil; clampOffset(card: card) })
                    .simultaneousGesture(MagnificationGesture()
                        .onChanged { value in
                            let start = zoomStart ?? edits.zoom
                            zoomStart = start
                            edits.zoom = min(max(start * value, 1), 4)
                        }
                        .onEnded { _ in zoomStart = nil; clampOffset(card: card) })
                }
                .aspectRatio(0.8, contentMode: .fit)
                .padding(.horizontal, 24)

                Picker("Mode", selection: $mode) {
                    Text("Crop").tag(Mode.crop)
                    Text("Filters").tag(Mode.filters)
                    Text("Adjust").tag(Mode.adjust)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)

                Group {
                    switch mode {
                    case .crop: cropControls
                    case .filters: filterStrip
                    case .adjust: adjustControls
                    }
                }
                .frame(height: 130)
                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            .foregroundStyle(Theme.ink)
            .tint(Theme.accentText)
            .background(Color(red: 0.035, green: 0.03, blue: 0.035).ignoresSafeArea())
            .nagisenSheetBar(String(localized: "Edit photo"), onClose: { dismiss() }, actionTitle: String(localized: "Done")) {
                onDone(PhotoEditor.render(edits, from: original), edits)
                dismiss()
            }
            .task {
                let base = PhotoEditor.apply(PhotoEdits(), to: original, maxEdge: 1000)
                small = base
                refresh()
                var made: [PhotoEdits.Filter: UIImage] = [:]
                for filter in PhotoEdits.Filter.allCases {
                    var look = PhotoEdits(); look.filter = filter
                    made[filter] = PhotoEditor.apply(look, to: base, maxEdge: 160)
                }
                thumbnails = made
            }
            .onChange(of: edits) { old, new in
                // Moving and zooming need no new pixels; everything else does.
                var a = old, b = new
                a.offset = .zero; b.offset = .zero; a.zoom = 1; b.zoom = 1
                if a != b { refresh() }
            }
        }
    }

    private func refresh() {
        guard let small else { return }
        var look = edits
        look.offset = .zero; look.zoom = 1
        preview = PhotoEditor.apply(look, to: small, maxEdge: 1000)
    }

    private func clampOffset(card: CGSize) {
        guard let preview else { return }
        let frame = PhotoEditor.frame(for: preview.size, in: card, edits: edits)
        edits.offset = CGSize(width: (frame.midX - card.width / 2) / card.width, height: (frame.midY - card.height / 2) / card.height)
    }

    private var cropControls: some View {
        VStack(spacing: 14) {
            Text("Drag to move, pinch to zoom.").font(.footnote).foregroundStyle(Theme.muted)
            HStack(spacing: 30) {
                cropButton("rotate.left", String(localized: "Rotate")) { edits.quarterTurns -= 1 }
                cropButton("arrow.left.and.right.righttriangle.left.righttriangle.right", String(localized: "Flip")) { edits.flipped.toggle() }
                cropButton("arrow.counterclockwise", String(localized: "Reset")) {
                    edits.quarterTurns = 0; edits.flipped = false; edits.zoom = 1; edits.offset = .zero
                }
            }
        }
    }

    private var filterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(PhotoEdits.Filter.allCases) { filter in
                    Button { edits.filter = filter } label: {
                        VStack(spacing: 6) {
                            Group {
                                if let thumbnail = thumbnails[filter] {
                                    Image(uiImage: thumbnail).resizable().scaledToFill()
                                } else {
                                    Theme.ink.opacity(0.06)
                                }
                            }
                            .frame(width: 72, height: 90)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(edits.filter == filter ? Theme.accentText : .clear, lineWidth: 2))
                            Text(filter.name).font(.caption2.weight(edits.filter == filter ? .semibold : .regular))
                                .foregroundStyle(edits.filter == filter ? Theme.accentText : Theme.ink)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(edits.filter == filter ? .isSelected : [])
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var adjustControls: some View {
        VStack(spacing: 14) {
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
        }
    }

    private func cropButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.title3)
                Text(label).font(.caption)
            }
            .frame(minWidth: 60, minHeight: 56)
        }
        .buttonStyle(.plain)
    }
}
