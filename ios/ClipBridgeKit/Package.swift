// swift-tools-version: 5.9
// 固定 Swift 5 语言模式：App 的三个 target 默认 MainActor 隔离 + Approachable Concurrency，
// 这里用 5.9 的工具版本让包保持 nonisolated 默认且只报警告，避免跨模块调用时的 Swift 6 严格并发错误。
import PackageDescription

let package = Package(
    name: "ClipBridgeKit",
    // macOS 条目只是为了在 Mac 上直接 `swift test`；Swift 6.4 工具链本身就要求 macOS 14，写低了也会被抬到 14。
    // App 本身是 iOS 17.6。
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ClipBridgeKit", targets: ["ClipBridgeKit"]),
    ],
    targets: [
        .target(name: "ClipBridgeKit"),
        .testTarget(name: "ClipBridgeKitTests", dependencies: ["ClipBridgeKit"]),
    ]
)
