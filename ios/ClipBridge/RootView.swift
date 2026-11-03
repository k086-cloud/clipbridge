import SwiftUI
import ClipBridgeKit

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var showScanner = false
    @State private var showManualEntry = false
    @State private var showUnpairConfirmation = false
    @State private var actionError: String?
    /// 扫到的码先存着，等扫码 sheet 完全关闭（onDismiss）再交给 model：同一次渲染里关一个 sheet 又开另一个会被 SwiftUI 丢掉。
    @State private var scannedCode: String?

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                if let configurationError = model.configurationError {
                    Section {
                        Label(configurationError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Section("配对状态") {
                    PairingStatusView(state: model.pairingState)
                }

                Section("配对") {
                    Button {
                        showScanner = true
                    } label: {
                        Label("扫描电脑上的二维码", systemImage: "qrcode.viewfinder")
                    }
                    Button {
                        showManualEntry = true
                    } label: {
                        Label("手动输入地址和 token", systemImage: "keyboard")
                    }
                    if model.pairingInfo != nil {
                        Button {
                            model.startConnectionTest()
                        } label: {
                            Label("测试连接", systemImage: "antenna.radiowaves.left.and.right")
                        }
                        .disabled(model.connectionTest.isRunning)
                        Button(role: .destructive) {
                            showUnpairConfirmation = true
                        } label: {
                            Label("解除配对", systemImage: "xmark.circle")
                        }
                    }
                }

                if let report = model.connectionTest.report {
                    Section("连接测试") {
                        ConnectionReportView(report: report, isRunning: model.connectionTest.isRunning)
                    }
                }

                Section("键盘与共享") {
                    NavigationLink {
                        SetupGuideView()
                    } label: {
                        Label("开启 ClipBridge 键盘", systemImage: "keyboard.badge.ellipsis")
                    }
                    Button {
                        openURL(URL(string: UIApplication.openSettingsURLString)!)
                    } label: {
                        Label("打开 ClipBridge 的系统设置", systemImage: "gear")
                    }
                    Text("设置页里一直有「键盘」（开启、允许完全访问）；「本地网络」和「相机」要在 App 第一次申请过之后才会出现。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Text("电脑 → 手机：切到 ClipBridge 键盘，点卡片插入。手机 → 电脑：选中文字 → 分享 → ClipBridge。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("用法")
                }
            }
            .navigationTitle("ClipBridge")
        }
        .sheet(isPresented: $showScanner, onDismiss: {
            if let code = scannedCode {
                scannedCode = nil
                model.handleScannedCode(code)
            }
        }) {
            ScanPairingView { code in
                scannedCode = code
            }
        }
        .sheet(isPresented: $showManualEntry) {
            ManualPairingView()
        }
        .sheet(item: $model.pendingPairing) { pending in
            PairingConfirmView(pending: pending)
        }
        .alert("无法识别配对信息", isPresented: Binding(
            get: { model.pairingInputError != nil },
            set: { if !$0 { model.pairingInputError = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(model.pairingInputError ?? "")
        }
        .confirmationDialog("解除配对后，键盘和共享扩展都无法再连接电脑。", isPresented: $showUnpairConfirmation, titleVisibility: .visible) {
            Button("解除配对", role: .destructive) {
                do {
                    try model.unpair()
                } catch {
                    actionError = error.localizedDescription
                }
            }
        }
        .alert("操作失败", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
        .onAppear {
            model.refresh()
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            model.scenePhase = phase
        }
    }
}

struct PairingStatusView: View {
    let state: PairingState

    var body: some View {
        switch state {
        case .notPaired:
            VStack(alignment: .leading, spacing: 6) {
                Label("尚未配对", systemImage: "link.badge.plus")
                    .font(.headline)
                Text("在电脑上运行 ClipBridge 服务，终端会打印一个二维码；用下面的「扫描」对准它。token 和剪贴板内容在局域网内明文传输，请只在家用 Wi-Fi 或手机热点下使用。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case let .paired(info):
            VStack(alignment: .leading, spacing: 6) {
                Label("已配对", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                LabeledContent("电脑", value: "\(info.host):\(String(info.port))")
                LabeledContent("token", value: info.token.maskedToken)
            }
        case let .tokenUnavailable(endpoint, reason):
            VStack(alignment: .leading, spacing: 6) {
                Label("地址已保存，但读不到 token", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                LabeledContent("电脑", value: "\(endpoint.host):\(String(endpoint.port))")
                Text(reason.localizedDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("重新扫码或手动输入一次即可修复。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ConnectionReportView: View {
    let report: ConnectionReport
    let isRunning: Bool

    var body: some View {
        stepRow("连通性（/health）", report.health)
        stepRow("token（/clip/history）", report.latest)
        if let hint = report.hint {
            Label(hint, systemImage: "lightbulb")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        if !isRunning, report.isSuccess {
            Label("一切正常。下一步：开启 ClipBridge 键盘。", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
        }
    }

    @ViewBuilder
    private func stepRow(_ title: String, _ step: ConnectionReport.Step) -> some View {
        switch step {
        case .pending:
            HStack {
                if isRunning {
                    ProgressView()
                } else {
                    Image(systemName: "minus.circle").foregroundStyle(.secondary)
                }
                Text(title)
            }
        case let .ok(detail):
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        case let .failed(detail):
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: "xmark.circle.fill").foregroundStyle(.red)
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

#Preview("未配对") {
    RootView()
        .environment(AppModel(store: SharedPairingStore.inMemory()))
}

#Preview("已配对") {
    RootView()
        .environment(AppModel(store: SharedPairingStore.inMemory(PairingInfo(host: "192.168.1.23", port: 8765, token: "K3fexampleexampleexample"))))
}
