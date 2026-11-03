//
//  ClipBridgeApp.swift
//  ClipBridge
//
//  Created by Charles Chen on 11/1/26.
//

import SwiftUI

@main
struct ClipBridgeApp: App {
    @State private var model = AppModel.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                // 相机 App 扫到 clipbridge://pair?… 二维码、或别的 App 打开配对链接时从这里进来；先确认再保存。
                .onOpenURL { url in
                    model.handleIncomingURL(url)
                }
        }
    }
}
