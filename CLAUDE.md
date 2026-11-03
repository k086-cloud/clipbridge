# ClipBridge

Windows 电脑 ↔ iPhone 剪贴板同步。Windows 端 Python 服务 + iOS 键盘扩展（电脑→手机）+ iOS 共享扩展（手机→电脑）。
当前状态：Windows 端 v0.1（纯文本）已完成；iOS 端在 Mac 上开发中——阶段 0（签名与 capability 实测）完成，阶段 1 的 `ClipBridgeKit` 已写好待链接进工程，详见「iOS 端」。

## 仓库结构（monorepo）
- `windows-server/` — Python 服务（FastAPI），包 `clipbridge_server/`
- `ios/` — Xcode 27 工程 `ClipBridge.xcodeproj`（JSON 格式 `project.xcproj`）+ 三个 target 目录 + 本地 Swift Package `ClipBridgeKit/`
- 远程仓库：github.com/k086-cloud/clipbridge（私有），分支 main

## Windows 端

### 模块
- `history.py` — 内存 deque 保留 history_size 条（默认 20）；`ClipItem{id, content, timestamp(ISO 本地时区，精确到毫秒), source: "pc"|"phone"}`，id 为 uuid4 hex
- `config.py` — `windows-server/config.json`（首次运行生成 token = `secrets.token_urlsafe(32)`；host 0.0.0.0；port 8765；poll_interval_ms 300；max_text_bytes 102400；history_size 20）。**config.json 含 token，已 gitignore，绝不能提交。**
- `auth.py` — `Authorization: Bearer <token>`，常量时间比较，失败返回 401 + WWW-Authenticate
- `clipboard.py` — pyperclip 后端；`ClipboardMonitor` 每 300ms 轮询；防回环：「读剪贴板 + 比较 last_seen」和「写剪贴板 + 更新 last_seen」在同一把锁里
- `api.py` — FastAPI 路由；Content-Length 中间件提前拦超大请求；JSON 响应带 `charset=utf-8`
- `pairing.py` — 局域网 IP（UDP connect 技巧）、配对 URL、终端 ASCII 二维码
- `cli.py` — `python -m clipbridge_server [--port] [--host] [--no-qr] [--log-level] [--config]`

### API 契约（iOS 端以此为准）
- `GET /health` — 免鉴权；返回 `{status, version, history_items, monitor_running, uptime_seconds, max_text_bytes, history_size}`（后两个 0.2.0 起才有，iOS 端按可选解析）
- `GET /clip/latest` — 最新一条，空则 404（iOS 端不用它：404 和「host 指错」分不开，改用 `history?limit=1`）
- `GET /clip/history?limit=N` — N ≥ 1（0、负数、非数字返回 422），超过 history_size 时截断为 history_size（0.1 版是 422，iOS 端对旧服务端仍有 422 → limit=1 的退化），省略时取全部；最新在前；响应为 `{"items": [...]}`
- `POST /clip`，body `{"content": "..."}` — 写入电脑剪贴板，记为 source=phone，返回 201；content 为空返回 422；UTF-8 编码超 max_text_bytes（默认 102400 字节）返回 413；写剪贴板失败返回 503
- 除 /health 外都要 `Authorization: Bearer <token>`，否则 401
- 配对二维码内容：`clipbridge://pair?host=<ip>&port=<port>&token=<token>`

### 开发命令（在 windows-server/ 下）
- 建环境：`python -m venv .venv`，然后 `.venv\Scripts\pip install -r requirements.txt`（跑测试还需 `.venv\Scripts\pip install -r requirements-dev.txt`，含 pytest、httpx）
- 启动：`.venv\Scripts\python.exe -m clipbridge_server`
- 测试：`.venv\Scripts\python.exe -m pytest`（剪贴板用 FakeClipboard mock，不碰真实剪贴板）
- 改了 API 或防回环逻辑必须补测试，全部通过再提交

### 已知坑
- `api.py` 不能加 `from __future__ import annotations`，Annotated Query 引用闭包变量会解析失败
- 启动时会把当前剪贴板内容记为第一条 pc 记录（只在内存；剪贴板为空或超过 max_text_bytes 时不记录）
- 校园网常有 AP 隔离，手机连不上电脑时换家用路由或手机热点
- 防火墙：首次启动允许 Python 访问专用网络，或管理员执行 `netsh advfirewall firewall add rule name="ClipBridge 8765" dir=in action=allow protocol=TCP localport=8765`
- PowerShell 5.1 下中文乱码靠响应头 charset=utf-8 解决，不要去掉

## iOS 端

### 现状（2026-11-03）
- 阶段 0、1 完成：工程、三个 target、App Groups + Keychain Sharing 都已签名装到真机，codesign 实测 entitlements 正确；`ClipBridgeKit` 已作为本地包链接到三个 target，`swift test` 全过
- 阶段 2 主 App 真机验收通过：App 内扫码 / 确认 / 保存、测试连接两项全绿、401 和连不上的提示、系统相机扫码弹「Open in ClipBridge」直达确认页、AppIdentifierPrefix 展开、`SharedPairingStore.live()` 和 Keychain 写入都正常。**本地网络权限弹窗没测到**：校园网里手机和电脑在不同子网、流量经路由转发，iOS 不把它当本地网络（TN3179 的定义），从不弹窗、设置里也没有 ClipBridge 条目；-1009 那条路径留到手机热点下补测
- 阶段 3 键盘扩展真机验收通过（2026-11-04）：没开完全访问时能读 App Group 里的地址并提示；开了之后拉取卡片、插入、刷新、发送剪贴板（弹「允许粘贴」）都正常。代码在 `ios/ClipBridgeKeyboard/`（KeyboardViewController + KeyboardView，纯 UIKit）。键盘里的几条经验：状态行必须固定高度（否则 UIStackView 让它吃掉全部高度，卡片区域被压成 0 pt，布局不报错）；卡片是 UIControl，滚动视图要重写 `touchesShouldCancel(in:)` 返回 true 才能按住拖动；隐藏的地球键宽度约束要用 999 优先级（UIStackView 隐藏时加 required 的 width == 0）；横屏高度用 190（键盘跟随宿主方向，和主 App 锁竖屏无关）；`UIPasteboard.string` 在 iOS 16+ 每次都可能弹「允许粘贴」，返回 nil 表示用户拒绝，不是剪贴板为空
- 阶段 4 共享扩展：`ios/ClipBridgeShare/ShareViewController.swift`（纯 UIKit），真机 SDK 构建通过，待真机复验。**取文字的坑（2026-11-04 真机）**：Safari 分享选中文字时 `loadDataRepresentation(for: .plainText)` 给的是 NSKeyedArchiver 归档的 bplist，用 `.utf16` 硬解会变成「扰汩猿」乱码发到电脑。现在顺序是 `loadObject(ofClass: NSString.self)` → `loadItem(forTypeIdentifier: public.plain-text)`（iOS 27 SDK 标 deprecated 但可用）→ `loadObject(NSAttributedString)` → 原始 Data 经 `ClipBridgeKit.SharedTextDecoder` 严格校验（合法 UTF-8 或带 BOM 的 UTF-16、不含 NUL；bplist 只按 NSKeyedUnarchiver 解 NSAttributedString/NSString）→ `attributedContentText`；全失败报错不发送，错误里带 `registeredTypeIdentifiers`，控制台也打印每个附件的类型；POST /clip 成功后 0.8 秒 `completeRequest`，失败显示原因 + 可重试时给「重试」，关闭用 `cancelRequest(withError:)`（用户取消是 NSUserCancelledError，失败是自定义域 + 原因）；超时 8 s / 12 s（别用键盘那套 3 秒）
- 无害的控制台日志：首次访问 App Group UserDefaults 的 CFPrefs「detaching from cfprefsd」、相机关闭时的 FigCaptureSourceRemote err=-17281
- 签名：免费 Apple ID（Personal Team，Team ID `L24ST657GM`）。描述文件 7 天过期（过期后重新 ⌘R 覆盖安装即可，键盘启用状态保留）；每周最多注册 10 个 App ID、每台设备最多 3 个 App（扩展可能也计数）
- 真机：iPhone 17 Pro Max「char」，iOS 26.6.1。Xcode 27.2 只能给 iOS 17+ 的设备装调试包；部署目标 iOS 17.6（Xcode 27.2 能选的最低值）
- 工程文件是 JSON 格式 `ios/ClipBridge.xcodeproj/project.xcproj`（不是 pbxproj），只有 Xcode 27+ 能打开。改构建设置、target、包依赖优先用 Xcode 27 自带的命令行工具 `xcrun xcodeproj`（`setting` / `target` / `group` / `pkg` 子命令，`xcrun xcodeproj pkg list -P ios/ClipBridge.xcodeproj` 可看包链接），手改 JSON 前先看清格式；改完用 `xcodebuild -project ios/ClipBridge.xcodeproj -scheme ClipBridge -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build` 验证（真机 SDK 加 `-sdk iphoneos -destination 'generic/platform=iOS' -allowProvisioningUpdates`）
- 三个 target 都是 Swift 5 语言模式 + Approachable Concurrency；只有主 App target 默认 MainActor 隔离，两个扩展默认 nonisolated。Kit 的 PairingStore/EndpointStore/TokenStore 都继承 Sendable，App 侧自写实现要么是只含 let 的 struct，要么是带锁的 `final class … @unchecked Sendable`
- ClipBridgeKit 已作为本地包链接到三个 target（静态链接，`ClipBridgeKit.o` 各链一份）；ios/ClipBridgeKit 必须和 ClipBridge.xcodeproj 同级，不能移进三个同步文件夹里

### Target 与 Bundle ID（已注册到 Personal Team，绝不要改名）
- `ClipBridge`（主 App，SwiftUI）= `com.charleschen.ClipBridge`
- `ClipBridgeKeyboard`（Custom Keyboard Extension）= `com.charleschen.ClipBridge.ClipBridgeKeyboard`
- `ClipBridgeShare`（Share Extension）= `com.charleschen.ClipBridge.ClipBridgeShare`
- 小写 `com.charleschen.clipbridge` 注册失败（Apple 判重不区分大小写），所以用了大写；只支持 iPhone（`TARGETED_DEVICE_FAMILY=1`，Designed for iPad 的 Mac/Vision 目标已关）

### Capability（三个 target 都有，已实测签进包）
- App Groups `group.com.charleschen.ClipBridge`（Personal Team + Xcode 27.2 实测可用，没有「Personal development teams do not support」报错）
- Keychain Sharing `com.charleschen.clipbridge.shared`，运行时完整组名 `L24ST657GM.com.charleschen.clipbridge.shared`，前缀从各 target Info.plist 的 `AppIdentifierPrefix = $(AppIdentifierPrefix)` 读
- 检查命令：`codesign -d --entitlements - --xml ~/Library/Developer/Xcode/DerivedData/ClipBridge-*/Build/Products/Debug-iphoneos/ClipBridge.app`（两个扩展在 `PlugIns/*.appex`）；描述文件 `security cms -D -i <bundle>/embedded.mobileprovision`

### 配对信息存储（已定）
- host/port 存 App Group 的 UserDefaults（键盘没开「允许完全访问」时按 Apple 文档仍可只读共享容器，能显示"已配对，待开启完全访问"）
- token 存共享 Keychain：kSecClassGenericPassword，service `com.charleschen.clipbridge.pairing`，account `token`，`AfterFirstUnlockThisDeviceOnly`，先删后加
- 封装在 `ClipBridgeKit.SharedPairingStore`：`load()` 返回 `PairingState`（notPaired / paired / tokenUnavailable(reason)），`save` 先写 Keychain 再写地址；真机用 `SharedPairingStore.live()`（Info.plist 缺 AppIdentifierPrefix 时返回 nil，不静默降级），测试和预览用 `.inMemory()`

### ClipBridgeKit（`ios/ClipBridgeKit`，本地 Swift Package）
- `swift-tools-version: 5.9`（Swift 5 语言模式，别升到 6——App target 默认 MainActor 隔离，跨模块会报一堆并发错误）；platforms iOS 17 / macOS 12（macOS 只为了 `swift test`）；只 import Foundation 和 Security，禁止 UIKit
- 模块：`PairingInfo`/`PairingEndpoint`、`PairingURLParser`、`ClipItem`/`HistoryResponse`/`ClipBridgeJSON`、`ClipBridgeError`、`ClipBridgeClient`、`PairingStore`（协议 + `SharedPairingStore`、`UserDefaultsEndpointStore`、`InMemory*`）、`KeychainTokenStore`/`KeychainError`/`KeychainAccessGroup`、`ClipBridgeIdentifiers`
- 客户端约定：任何 2xx 算成功；`health()` 必须解出 `HealthResponse`（解不出 = 对面不是 ClipBridge）；`latest()` 走 `history?limit=1`，空数组 → nil，真 404 → `.notFound`（host 指错）；`recentHistory(preferredLimit: 5)` 收到 422 退化成 limit=1（省略 limit 会拉全部，不能当兜底）；422 错误体是数组、其他是字符串；时间戳用 ISO8601DateFormatter 带毫秒；发送前本地拦空内容和 UTF-8 超 102400 字节；超时 3 s / 5 s；`transport(.notConnectedToInternet)` 多半是本地网络权限被拒，`.appTransportSecurityRequiresSecureConnection` 是 ATS 没放行，`underlying(NSPOSIXErrorDomain, 1)` 是扩展沙盒禁网；错误的中文文案在 `ClipBridgeMessages.swift`（LocalizedError）
- 测试：`cd ios/ClipBridgeKit && swift test`（网络用 MockURLProtocol，Keychain 用 InMemoryTokenStore；真 Keychain 在 macOS 命令行无签名跑不了，只在真机验证）。改 API 契约或存储逻辑必须补测试

### Info.plist（已加）
- 三个 target：`AppIdentifierPrefix = $(AppIdentifierPrefix)`、`NSAppTransportSecurity → NSAllowsLocalNetworking = YES`（ATS 对扩展也生效，不能只加主 App）
- 主 App `ios/ClipBridge/Info.plist`（与生成的 Info.plist 合并；工程里用 membership-exceptions 把它排除出资源）：`NSLocalNetworkUsageDescription`（只放主 App，不放扩展）、`NSCameraUsageDescription`、URL scheme `clipbridge`
- 键盘：`RequestsOpenAccess = YES`（否则没有「允许完全访问」开关，也没网络）
- 共享扩展：`NSExtensionActivationRule` 是字典 `{NSExtensionActivationSupportsText: true}`（只对文字出现在分享面板，分享网址不出现）；`NSExtensionPrincipalClass = $(PRODUCT_MODULE_NAME).ShareViewController`（自定义 UIKit 界面，模板的 SLComposeServiceViewController 和 storyboard 已删）；分享面板里显示名 `CFBundleDisplayName = ClipBridge`

### 已知坑
- 本地网络权限按 App 记录、扩展继承；必须由主 App 前台先触发（「测试连接」）；iOS 18 起没有 NSLocalNetworkUsageDescription 弹窗不出现；被拒表现为 URLError -1009；模拟器不支持，只能真机测
- 键盘没开完全访问时禁一切网络；Keychain 能否读 Apple 没写，以 `hasFullAccess` 为准，不用 Keychain 失败推断
- 内存：键盘约 50–70 MB、共享扩展约 120 MB，超了静默被杀；键盘只显示截断文本
- Xcode 27 新建工程默认创建嵌套 git 仓库，建工程时取消勾选（这次已删掉 ios/.git）
- 服务端 0.2.0 起 `history?limit=` 超过 history_size 会截断；Windows 上的服务要 `git pull` 后重启才生效，旧服务端仍返回 422（客户端有退化处理）

### 后续阶段
- 阶段 4 共享扩展待真机验证 → 阶段 5 收尾（README、CLAUDE.md 定稿、热点下补测本地网络弹窗）

## 约定
- 第一版只做纯文本；图片/文件、历史持久化、mDNS、HTTPS、开机自启、托盘图标都是后续
- 按功能分多次有意义的 commit，不要一个大 commit
- 不要提交任何含 token、密钥的文件
- 改动涉及 API 时，同步更新本文件的"API 契约"和 windows-server/README.md
