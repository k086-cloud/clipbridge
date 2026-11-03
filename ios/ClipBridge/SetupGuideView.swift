import SwiftUI
import UIKit

/// 引导用户把键盘加到系统里并打开「允许完全访问」。系统没有能直接跳到「添加新键盘」的链接，
/// 只能跳到本 App 的设置页（那里有「键盘」一栏，可以开启键盘和完全访问）。
struct SetupGuideView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section("1. 添加键盘") {
                step("打开「设置 → 通用 → 键盘 → 键盘 → 添加新键盘」")
                step("在「第三方键盘」里选 ClipBridgeKeyboard")
            }
            Section("2. 允许完全访问") {
                step("回到「键盘」列表，点 ClipBridgeKeyboard，打开「允许完全访问」，弹窗选「允许」")
                Text("没开这个开关，键盘不能联网，也就拿不到电脑的剪贴板。它只用来访问局域网里你自己的电脑。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("3. 使用") {
                step("在任意输入框里长按地球键，切到 ClipBridge 键盘，点卡片即可插入电脑上复制的内容")
                step("手机 → 电脑：选中文字 → 分享 → ClipBridge")
            }
            Section {
                Button {
                    openURL(URL(string: UIApplication.openSettingsURLString)!)
                } label: {
                    Label("打开 ClipBridge 的系统设置", systemImage: "gear")
                }
                Text("这一页里有「键盘」（开启、允许完全访问）、「本地网络」和「相机」三个开关。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("开启键盘")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func step(_ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "arrow.turn.down.right")
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        SetupGuideView()
    }
}
