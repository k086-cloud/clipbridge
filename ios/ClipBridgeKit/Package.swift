// swift-tools-version: 5.9
// 固定 Swift 5 语言模式。工程里三个 target 都是 Swift 5 模式 + Approachable Concurrency；
// 只有主 App target 默认 MainActor 隔离，两个扩展 target 默认 nonisolated。
// 这里用 5.9 的工具版本让包保持 nonisolated 默认且只报警告，避免跨模块调用时的 Swift 6 严格并发错误。
// 注意：PairingStore / EndpointStore / TokenStore 都继承 Sendable，App 侧自己写实现时要么是只含 let 的 struct，
// 要么是带锁的 final class + @unchecked Sendable（照 InMemory* 的写法）。
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
