import SwiftUI
import ClipBridgeKit

/// 扫码 / 链接解析出来的配对信息，保存前让用户确认一眼（clipbridge:// 这个 scheme 任何 App 都能注册，不能见链接就存）。
struct PairingConfirmView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let pending: PendingPairing
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("将与这台电脑配对") {
                    LabeledContent("地址", value: pending.info.host)
                    LabeledContent("端口", value: String(pending.info.port))
                    LabeledContent("token", value: pending.info.token.maskedToken)
                }
                Section {
                    Text("保存后会覆盖之前的配对。地址存在 App Group，token 存在共享 Keychain，键盘和共享扩展都能读到。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("确认配对")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        model.pendingPairing = nil
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        do {
                            try model.confirmPendingPairing()
                            dismiss()
                        } catch {
                            saveError = error.localizedDescription
                        }
                    }
                }
            }
            .alert("保存失败", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
        }
    }
}

/// 扫不了码时的备用路径：手动填终端里打印的 host / port / token。
struct ManualPairingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var host = ""
    @State private var portText = "8765"
    @State private var token = ""
    @State private var saveError: String?

    private var port: Int? { Int(portText.trimmingCharacters(in: .whitespaces)) }
    private var trimmedHost: String { host.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedToken: String { token.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var hostProblem: String? {
        if trimmedHost.isEmpty || PairingEndpoint.isValidHost(trimmedHost) {
            return nil
        }
        if trimmedHost.contains(":") {
            return "只填 IP 或主机名，不要带端口；含冒号的只能是 IPv6 地址"
        }
        return "不能含空格或 / ? # @ [ ]"
    }

    private var portProblem: String? {
        if portText.isEmpty { return nil }
        guard let port, PairingEndpoint.isValidPort(port) else { return "应为 1–65535 的整数" }
        return nil
    }

    /// 已配对时留空 token 表示沿用当前的 token（只改地址的场景），不用把密钥搬进明文输入框。
    private var effectiveToken: String? {
        trimmedToken.isEmpty ? model.pairingInfo?.token : trimmedToken
    }

    private var canSave: Bool {
        guard let port, effectiveToken != nil else { return false }
        return PairingEndpoint.isValidHost(trimmedHost) && PairingEndpoint.isValidPort(port)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("电脑的局域网 IP，例如 192.168.1.23", text: $host)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if let hostProblem {
                        Text(hostProblem).font(.footnote).foregroundStyle(.red)
                    }
                } header: {
                    Text("地址（host）")
                } footer: {
                    Text("电脑终端启动 ClipBridge 时打印的 LAN address。")
                }

                Section {
                    TextField("8765", text: $portText)
                        .keyboardType(.numberPad)
                    if let portProblem {
                        Text(portProblem).font(.footnote).foregroundStyle(.red)
                    }
                } header: {
                    Text("端口")
                }

                Section {
                    TextField("终端里打印的 token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text("token")
                } footer: {
                    Text(model.pairingInfo == nil ? "区分大小写，整段复制最稳妥。" : "区分大小写，整段复制最稳妥。已配对时留空则沿用当前 token。")
                }

                if let current = model.pairingInfo {
                    Section {
                        Button("填入当前地址（\(current.host):\(String(current.port))）") {
                            host = current.host
                            portText = String(current.port)
                        }
                    }
                }
            }
            .navigationTitle("手动输入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        guard let port, let token = effectiveToken else { return }
                        do {
                            try model.pair(PairingInfo(host: trimmedHost, port: port, token: token))
                            dismiss()
                        } catch {
                            saveError = error.localizedDescription
                        }
                    }
                    .disabled(!canSave)
                }
            }
            .alert("保存失败", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
        }
    }
}

#Preview("确认") {
    PairingConfirmView(pending: PendingPairing(info: PairingInfo(host: "192.168.1.23", port: 8765, token: "K3fexampleexampleexample")))
        .environment(AppModel(store: SharedPairingStore.inMemory()))
}

#Preview("手动输入") {
    ManualPairingView()
        .environment(AppModel(store: SharedPairingStore.inMemory()))
}
