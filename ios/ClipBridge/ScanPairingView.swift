import AVFoundation
import SwiftUI
import UIKit

/// 扫描终端里的配对二维码。用 AVCaptureMetadataOutput 而不是 VisionKit 的 DataScannerViewController：
/// 后者要 A12 以上芯片，前者在 iOS 17 支持的所有机型上都能用，而且这里只需要识别一个 QR。
struct ScanPairingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let onCode: (String) -> Void

    @State private var authorization = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        NavigationStack {
            Group {
                switch authorization {
                case .authorized:
                    QRScannerView { code in
                        dismiss()
                        onCode(code)
                    }
                    .ignoresSafeArea()
                    .overlay(alignment: .bottom) {
                        Text("对准电脑终端里打印的二维码")
                            .padding(10)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.bottom, 32)
                    }
                case .notDetermined:
                    ProgressView("请求相机权限…")
                        .task {
                            let granted = await AVCaptureDevice.requestAccess(for: .video)
                            authorization = granted ? .authorized : .denied
                        }
                default:
                    ContentUnavailableView {
                        Label("没有相机权限", systemImage: "camera.fill")
                    } description: {
                        Text("扫码需要相机。你也可以改用「手动输入」。")
                    } actions: {
                        Button("去设置里打开相机") {
                            openURL(URL(string: UIApplication.openSettingsURLString)!)
                        }
                    }
                }
            }
            .navigationTitle("扫描配对二维码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

struct QRScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let controller = QRScannerViewController()
        controller.onCode = onCode
        return controller
    }

    func updateUIViewController(_ controller: QRScannerViewController, context: Context) {
        controller.onCode = onCode
    }
}

final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.charleschen.ClipBridge.scanner")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var configured = false
    private var delivered = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        delivered = false
        guard configured else { return }
        let session = self.session
        // startRunning 会阻塞，Apple 要求放到后台队列。
        sessionQueue.async {
            if !session.isRunning {
                session.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        let session = self.session
        sessionQueue.async {
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    private func configureSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            showUnavailable("没有可用的相机")
            return
        }
        session.beginConfiguration()
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            showUnavailable("相机不支持识别二维码")
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        session.commitConfiguration()

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        previewLayer = layer
        configured = true
    }

    private func showUnavailable(_ message: String) {
        let label = UILabel()
        label.text = message
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ])
    }

    // 回调队列设成了 main，这里只是把隔离身份交还给 MainActor。
    nonisolated func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        let values = metadataObjects.compactMap { object -> String? in
            guard let code = object as? AVMetadataMachineReadableCodeObject, code.type == .qr else { return nil }
            return code.stringValue
        }
        guard let value = values.first else { return }
        MainActor.assumeIsolated {
            deliver(value)
        }
    }

    private func deliver(_ value: String) {
        guard !delivered else { return }
        delivered = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        let session = self.session
        sessionQueue.async {
            session.stopRunning()
        }
        onCode?(value)
    }
}
