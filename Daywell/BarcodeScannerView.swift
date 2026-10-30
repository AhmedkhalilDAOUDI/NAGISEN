import AVFoundation
import SwiftUI

struct BarcodeScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var cameraAllowed = false
    @State private var barcode = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var barcodeFocused: Bool
    let forPricing: Bool
    let onFound: (Food) -> Void

    init(forPricing: Bool = false, onFound: @escaping (Food) -> Void) {
        self.forPricing = forPricing
        self.onFound = onFound
    }

    var body: some View {
        VStack(spacing: 18) {
            NagisenHeader("Scan barcode", subtitle: "Find food from its label.", symbol: "xmark", onBack: { dismiss() })
            Text("Place the barcode inside the frame")
                .font(.subheadline).foregroundStyle(Theme.muted)
            Group {
                if cameraAllowed {
                    ScannerCameraView { code in
                        barcode = code
                        lookup()
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(.white.opacity(0.9), lineWidth: 2)
                            .frame(width: 255, height: 145)
                    }
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "barcode.viewfinder").font(.largeTitle)
                        Text("Camera unavailable. Enter the number below.")
                            .font(.subheadline).multilineTextAlignment(.center)
                    }
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)
                    .background(Theme.surface)
                }
            }
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 18))

            HStack {
                TextField("Barcode number", text: $barcode)
                    .keyboardType(.numberPad)
                    .textContentType(.none)
                    .focused($barcodeFocused)
                if isLoading { SwiftUI.ProgressView() }
            }
            .padding(15)
            .nagisenGlass(in: RoundedRectangle(cornerRadius: 12), tint: Theme.surface.opacity(0.18))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))

            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(Theme.accentText)
                    .multilineTextAlignment(.center)
            }
            NagisenPrimaryButton(forPricing ? "Find product" : "Look up food",
                                 enabled: !isLoading && !barcode.isEmpty) { lookup() }
            Text(forPricing
                 ? "The barcode identifies the product. Check the shelf or receipt before saving a price."
                 : "Barcode data from Open Food Facts. Check the label before logging.")
                .font(.footnote).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(22)
        .background(NagisenBackdrop())
        .tint(Theme.accentText)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { barcodeFocused = false }
            }
        }
        .onAppear(perform: requestCamera)
    }

    private func requestCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: cameraAllowed = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { cameraAllowed = granted }
            }
        default: cameraAllowed = false
        }
    }

    private func lookup() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let food = try await (forPricing
                    ? OpenFoodFactsService().lookupForPricing(barcode: barcode)
                    : OpenFoodFactsService().lookup(barcode: barcode))
                isLoading = false
                onFound(food)
            } catch {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct ScannerCameraView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.onCode = onCode
        return controller
    }

    func updateUIViewController(_ controller: ScannerViewController, context: Context) {
        controller.onCode = onCode
    }
}

private final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    private var lastCode = ""
    private var lastScan = Date.distantPast

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let camera = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else { return }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.ean8, .ean13, .upce, .code128]
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        preview = layer
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.stopRunning()
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let code = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
        guard code != lastCode || Date.now.timeIntervalSince(lastScan) > 5 else { return }
        lastCode = code
        lastScan = .now
        onCode?(code)
    }
}
