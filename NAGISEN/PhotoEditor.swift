import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Everything done to a photo before it goes under a share card. It starts as the untouched original:
/// nothing is cropped, turned or filtered unless you choose it. Kept apart from the image so reopening
/// starts from the original with the same choices.
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
            case .fade: String(localized: "Faded")
            case .chrome: String(localized: "Chrome")
            case .instant: String(localized: "Instant")
            case .warm: String(localized: "Warm")
            case .cool: String(localized: "Cool")
            }
        }
    }

    enum Crop: String, CaseIterable, Identifiable {
        case original, free, square, portrait, story, wide
        var id: String { rawValue }
        var name: String {
            switch self {
            case .original: String(localized: "Original")
            case .free: String(localized: "Free")
            case .square: "1:1"
            case .portrait: "4:5"
            case .story: "9:16"
            case .wide: "16:9"
            }
        }
        /// Width over height; nil for the whole photo or a free frame.
        var ratio: CGFloat? {
            switch self {
            case .original, .free: nil
            case .square: 1
            case .portrait: 4.0 / 5
            case .story: 9.0 / 16
            case .wide: 16.0 / 9
            }
        }
    }

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
    var filter = Filter.original
    /// How much of the filter shows, from none to all of it.
    var filterStrength: Double = 1
    var crop = Crop.original
    var quarterTurns = 0
    var flipped = false
    /// Inside a crop: 1 is the largest frame that fits, more zooms in.
    var zoom: Double = 1
    /// Inside a crop: where the frame sits, from -1 (left or top) to 1 (right or bottom).
    var offset = CGSize.zero
    /// A free crop, as fractions of the photo measured from its top left.
    var freeRect = CGRect(x: 0, y: 0, width: 1, height: 1)

    subscript(tool: Tool) -> Double {
        get { values[tool] ?? 0 }
        set { values[tool] = newValue == 0 ? nil : newValue }
    }
}

enum PhotoEditor {
    private static let context = CIContext()

    /// The photo with what you chose: turned, cropped, filtered and adjusted. With nothing chosen it comes back
    /// whole and unchanged. `maxEdge` keeps previews quick.
    static func apply(_ edits: PhotoEdits, to image: UIImage, maxEdge: CGFloat = 2400) -> UIImage {
        let base = upright(image, maxEdge: maxEdge)
        guard edits != PhotoEdits(), var input = CIImage(image: base) else { return base }
        for _ in 0..<((edits.quarterTurns % 4 + 4) % 4) { input = input.oriented(.right) }
        if edits.flipped { input = input.oriented(.upMirrored) }
        input = input.transformed(by: CGAffineTransform(translationX: -input.extent.minX, y: -input.extent.minY))
        let frame = edits.crop == .free ? freeCropRect(in: input.extent, edits.freeRect)
            : cropRect(in: input.extent, ratio: edits.crop.ratio, zoom: edits.zoom, offset: edits.offset)
        input = input.cropped(to: frame).transformed(by: CGAffineTransform(translationX: -frame.minX, y: -frame.minY))
        let extent = input.extent

        if edits.filter != .original {
            let styled = filtered(input, edits.filter).cropped(to: extent)
            input = edits.filterStrength >= 1 ? styled : input.applyingFilter("CIDissolveTransition", parameters: [
                kCIInputTargetImageKey: styled, kCIInputTimeKey: max(edits.filterStrength, 0)])
        }

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

    /// The part of the photo a crop keeps: the largest frame of that shape, zoomed and slid as chosen.
    /// Core Image counts y from the bottom, so a positive offset (down) moves the frame toward y = 0.
    static func cropRect(in extent: CGRect, ratio: CGFloat?, zoom: Double, offset: CGSize) -> CGRect {
        guard let ratio else { return extent }
        var width = extent.width, height = width / ratio
        if height > extent.height { height = extent.height; width = height * ratio }
        width /= max(zoom, 1); height /= max(zoom, 1)
        let slideX = (extent.width - width) / 2, slideY = (extent.height - height) / 2
        let clampedX = min(max(offset.width, -1), 1), clampedY = min(max(offset.height, -1), 1)
        let rect = CGRect(x: extent.midX + clampedX * slideX - width / 2, y: extent.midY - clampedY * slideY - height / 2,
                          width: width, height: height)
        return rect.integral.intersection(extent)
    }

    /// A free frame in Core Image's pixels, which count y from the bottom.
    static func freeCropRect(in extent: CGRect, _ fraction: CGRect) -> CGRect {
        CGRect(x: extent.minX + fraction.minX * extent.width, y: extent.minY + (1 - fraction.maxY) * extent.height,
               width: fraction.width * extent.width, height: fraction.height * extent.height).integral.intersection(extent)
    }

    enum CropCorner: CaseIterable { case topLeft, topRight, bottomLeft, bottomRight
        var left: Bool { self == .topLeft || self == .bottomLeft }
        var top: Bool { self == .topLeft || self == .topRight }
    }

    /// A free frame after a drag: a corner reshapes it, the middle (nil) moves it. It stays on the photo
    /// and never shrinks below a tenth of it.
    static func adjusted(_ rect: CGRect, corner: CropCorner?, by delta: CGSize) -> CGRect {
        let least: CGFloat = 0.1
        guard let corner else {
            return CGRect(x: min(max(rect.minX + delta.width, 0), 1 - rect.width),
                          y: min(max(rect.minY + delta.height, 0), 1 - rect.height), width: rect.width, height: rect.height)
        }
        var (minX, maxX, minY, maxY) = (rect.minX, rect.maxX, rect.minY, rect.maxY)
        if corner.left { minX = min(max(minX + delta.width, 0), maxX - least) } else { maxX = max(min(maxX + delta.width, 1), minX + least) }
        if corner.top { minY = min(max(minY + delta.height, 0), maxY - least) } else { maxY = max(min(maxY + delta.height, 1), minY + least) }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
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

/// The photo editor, laid out like Instagram's: Filter and Edit tabs under a big photo. Each Edit tool,
/// Crop included, opens its own panel with Cancel and Done. Hold the photo to see the original.
/// Nothing is cropped or filtered until you pick it.
struct PhotoEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let original: UIImage
    @State var edits: PhotoEdits
    let onDone: (UIImage, PhotoEdits) -> Void

    private enum Tab { case filter, edit }
    @State private var tab = Tab.edit
    @State private var tool: PhotoEdits.Tool?
    @State private var cropping = false
    /// The edits when a panel opened, so Cancel can put them back.
    @State private var before = PhotoEdits()
    @State private var dragStart: CGSize?
    @State private var preview: UIImage?
    /// A small copy for live previews, so sliders stay smooth.
    @State private var small: UIImage?
    @State private var thumbnails: [PhotoEdits.Filter: UIImage] = [:]
    @State private var comparing = false

    private var panelOpen: Bool { tool != nil || cropping }
    /// While choosing a free frame the whole photo shows, with the frame on top.
    private var freeCropping: Bool { cropping && edits.crop == .free }
    private var title: String {
        if let tool { return tool.name }
        return cropping ? String(localized: "Crop") : String(localized: "Edit")
    }

    var body: some View {
        // The stack keeps the bars clear of the status bar and home indicator inside a full-screen cover.
        NavigationStack { content.toolbar(.hidden, for: .navigationBar) }
    }

    private var content: some View {
        VStack(spacing: 0) {
            HStack {
                Button(String(localized: "Cancel")) { dismiss() }
                Spacer()
                Button(String(localized: "Done")) {
                    onDone(PhotoEditor.apply(edits, to: original), edits)
                    dismiss()
                }
                .fontWeight(.semibold)
            }
            .font(.body)
            .opacity(panelOpen ? 0.0001 : 1)
            .disabled(panelOpen)
            .overlay { Text(title).font(.system(size: 17, design: .serif)) }
            .padding(.horizontal, 20)
            .frame(height: 52)

            photo

            Group {
                if let tool {
                    sliderPanel(tool)
                } else if cropping {
                    cropPanel
                } else if tab == .filter {
                    filterRow
                } else {
                    toolRow
                }
            }
            .frame(height: 150)

            if !panelOpen {
                HStack(spacing: 40) {
                    tabButton(String(localized: "Filter"), .filter)
                    tabButton(String(localized: "Edit"), .edit)
                }
                .frame(height: 44)
            }
        }
        .foregroundStyle(Theme.ink)
        .tint(Theme.accentText)
        .background(Color(red: 0.035, green: 0.03, blue: 0.035).ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .task {
            let base = PhotoEditor.apply(PhotoEdits(), to: original, maxEdge: 1000)
            small = base
            refresh()
            var thumbs: [PhotoEdits.Filter: UIImage] = [:]
            for filter in PhotoEdits.Filter.allCases {
                var look = PhotoEdits()
                look.filter = filter
                thumbs[filter] = PhotoEditor.apply(look, to: base, maxEdge: 200)
            }
            thumbnails = thumbs
        }
        .onChange(of: edits) { _, _ in refresh() }
        .onChange(of: cropping) { _, _ in refresh() }
    }

    private var photo: some View {
        ZStack(alignment: .top) {
            if let shown = comparing ? small : preview {
                Image(uiImage: shown).resizable().scaledToFit()
                    .overlay {
                        if freeCropping {
                            GeometryReader { geo in FreeCropFrame(rect: $edits.freeRect, size: geo.size) }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: freeCropping ? 0 : 12, style: .continuous))
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
        .gesture(DragGesture(minimumDistance: 4)
            .onChanged { value in
                // While cropping, dragging the photo slides the frame across it.
                guard cropping, edits.crop.ratio != nil else { return }
                let start = dragStart ?? edits.offset
                dragStart = start
                edits.offset = CGSize(width: min(max(start.width - value.translation.width / 150, -1), 1),
                                      height: min(max(start.height - value.translation.height / 150, -1), 1))
            }
            .onEnded { _ in dragStart = nil },
            including: cropping ? .all : .none)
        .onLongPressGesture(minimumDuration: 0.12, perform: {}, onPressingChanged: { comparing = $0 && !cropping })
        .accessibilityHint(cropping ? String(localized: "Drag to move the crop") : String(localized: "Hold to see the original"))
    }

    private func tabButton(_ label: String, _ value: Tab) -> some View {
        Button(label) { tab = value }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tab == value ? Theme.ink : Theme.muted)
            .frame(minWidth: 64, minHeight: 44)
            .accessibilityAddTraits(tab == value ? .isSelected : [])
    }

    private func panelButtons(cancel: @escaping () -> Void, done: @escaping () -> Void) -> some View {
        HStack {
            Button(String(localized: "Cancel"), action: cancel)
            Spacer()
            Button(String(localized: "Done"), action: done).fontWeight(.semibold)
        }
        .frame(minHeight: 44)
    }

    private func sliderPanel(_ tool: PhotoEdits.Tool) -> some View {
        VStack(spacing: 14) {
            Text("\(Int((edits[tool] * 100).rounded()))").font(.system(size: 15, design: .serif).monospacedDigit())
            Slider(value: Binding(get: { edits[tool] }, set: { edits[tool] = ($0 * 100).rounded() / 100 }), in: tool.range)
            panelButtons(cancel: { edits = before; self.tool = nil }, done: { self.tool = nil })
        }
        .padding(.horizontal, 24)
    }

    private var cropPanel: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(PhotoEdits.Crop.allCases) { shape in
                    Button {
                        edits.crop = shape
                        edits.zoom = 1
                        edits.offset = .zero
                        edits.freeRect = CGRect(x: 0, y: 0, width: 1, height: 1)
                    } label: {
                        Text(shape.name).font(.caption.weight(.semibold))
                            .padding(.horizontal, 9).frame(height: 32)
                            .foregroundStyle(edits.crop == shape ? Theme.ink : Theme.muted)
                            .background(edits.crop == shape ? Theme.accent.opacity(0.35) : .clear, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.ink.opacity(0.16), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(edits.crop == shape ? .isSelected : [])
                }
            }
            HStack(spacing: 16) {
                Button { edits.quarterTurns = (edits.quarterTurns + 1) % 4 } label: {
                    Image(systemName: "rotate.right").frame(width: 44, height: 44)
                }
                .accessibilityLabel(String(localized: "Rotate"))
                Button { edits.flipped.toggle() } label: {
                    Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right").frame(width: 44, height: 44)
                }
                .accessibilityLabel(String(localized: "Flip"))
                if edits.crop == .free {
                    Text("Drag the corners, or the middle to move it").font(.caption).foregroundStyle(Theme.muted)
                    Spacer()
                } else if edits.crop != .original {
                    Image(systemName: "minus.magnifyingglass").foregroundStyle(Theme.muted)
                    Slider(value: $edits.zoom, in: 1...3)
                    Image(systemName: "plus.magnifyingglass").foregroundStyle(Theme.muted)
                } else {
                    Spacer()
                }
            }
            panelButtons(cancel: { edits = before; cropping = false }, done: { cropping = false })
        }
        .padding(.horizontal, 20)
    }

    private var filterRow: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(PhotoEdits.Filter.allCases) { filter in
                        Button {
                            if edits.filter != filter { edits.filter = filter; edits.filterStrength = 1 }
                        } label: {
                            VStack(spacing: 6) {
                                Text(filter.name).font(.caption2).foregroundStyle(edits.filter == filter ? Theme.ink : Theme.muted)
                                Group {
                                    if let thumb = thumbnails[filter] {
                                        Image(uiImage: thumb).resizable().scaledToFill()
                                    } else {
                                        Color.white.opacity(0.06)
                                    }
                                }
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.ink.opacity(edits.filter == filter ? 0.9 : 0), lineWidth: 1.5))
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(edits.filter == filter ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 20)
            }
            if edits.filter != .original {
                HStack(spacing: 12) {
                    Text("Strength").font(.caption).foregroundStyle(Theme.muted)
                    Slider(value: $edits.filterStrength, in: 0...1)
                    Text("\(Int((edits.filterStrength * 100).rounded()))").font(.caption.monospacedDigit()).frame(width: 30)
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var toolRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                let cropped = edits.crop != .original || edits.quarterTurns != 0 || edits.flipped
                Button { before = edits; cropping = true } label: {
                    toolLabel(String(localized: "Crop"), symbol: "crop", changed: cropped)
                }
                .buttonStyle(.plain)
                ForEach(PhotoEdits.Tool.allCases) { item in
                    Button { before = edits; tool = item } label: {
                        toolLabel(item.name, symbol: item.symbol, changed: edits[item] != 0)
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(edits[item] == 0 ? "" : "\(Int((edits[item] * 100).rounded()))")
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func toolLabel(_ name: String, symbol: String, changed: Bool) -> some View {
        VStack(spacing: 7) {
            Text(name).font(.caption2).foregroundStyle(changed ? Theme.ink : Theme.muted)
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .light))
                .frame(width: 62, height: 62)
                .overlay(Circle().strokeBorder(Theme.ink.opacity(changed ? 0.7 : 0.22), lineWidth: 1))
            Circle().fill(Theme.accentText).frame(width: 4, height: 4).opacity(changed ? 1 : 0)
        }
        .frame(width: 72)
    }

    private func refresh() {
        guard let small else { return }
        var shown = edits
        if freeCropping { shown.crop = .original }
        preview = PhotoEditor.apply(shown, to: small, maxEdge: 1000)
    }
}

/// The free crop frame over the whole photo: outside it is dimmed, corners reshape it, the middle moves it.
private struct FreeCropFrame: View {
    @Binding var rect: CGRect
    let size: CGSize
    @State private var start: CGRect?

    var body: some View {
        let frame = CGRect(x: rect.minX * size.width, y: rect.minY * size.height,
                           width: rect.width * size.width, height: rect.height * size.height)
        ZStack(alignment: .topLeading) {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: size))
                path.addRect(frame)
            }
            .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)
            Rectangle()
                .strokeBorder(.white.opacity(0.9), lineWidth: 1.5)
                .contentShape(Rectangle())
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
                .gesture(drag(nil))
                .accessibilityLabel(String(localized: "Crop frame"))
            ForEach(PhotoEditor.CropCorner.allCases, id: \.self) { corner in
                Circle().fill(.white)
                    .frame(width: 16, height: 16)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .offset(x: (corner.left ? frame.minX : frame.maxX) - 22, y: (corner.top ? frame.minY : frame.maxY) - 22)
                    .gesture(drag(corner))
            }
        }
    }

    private func drag(_ corner: PhotoEditor.CropCorner?) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let from = start ?? rect
                start = from
                rect = PhotoEditor.adjusted(from, corner: corner, by: CGSize(width: value.translation.width / max(size.width, 1),
                                                                               height: value.translation.height / max(size.height, 1)))
            }
            .onEnded { _ in start = nil }
    }
}
