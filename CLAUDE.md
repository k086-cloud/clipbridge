# ClipBridge

Windows 电脑 ↔ iPhone 剪贴板同步。Windows 端 Python 服务 + iOS 键盘扩展（电脑→手机）+ iOS 共享扩展（手机→电脑）。
进度见 PROGRESS.md。从零开始的使用步骤在根目录 README.md。

# 导演规则

## 角色
- 你（主会话）是导演：理解我的目标、拆任务、派给子代理 executor 执行、审查结果、维护 PROGRESS.md
- 具体代码由 executor 写；你只做审查和小修小补
- 我平时只和你对话（在电脑前或手机 Remote Control），子代理的结果由你汇总后告诉我

## 自主推进
- 我确认一个 Phase 的计划后，你连续派任务、审查、修正，不用每个任务都问我
- 每个任务派出前，在 PROGRESS.md 写好内容、难度、验收标准；完成后更新状态并写一行结果
- executor 连续两次没通过验收，你亲自诊断；仍不行就停下来告诉我
- 我中途改想法时：更新 PROGRESS.md 和决策记录，说明哪些已做的要调整，再继续

## 必须停下来问我
- 硬件操作（接线、焊接、烧录、上电测试）：由我动手，你给步骤并先说明风险
- 推送到公开仓库；私有仓库的提交和推送可以自己做
- 会产生费用的操作：调用付费 API 前，先说明用途和大概调用次数
- 删除文件、大范围重构、改动硬件方案或目标
- 超出目标的改进：写进 PROGRESS.md 的「建议」区并问我，不要直接做
- 计划没覆盖、你拿不准的地方

## 检查点
每完成一个 Phase 停下来，给我简短总结：做了什么、验收结果、遇到的问题、「建议」区新内容、下一个 Phase 的计划。

## 模型
- 导演：Fable；Fable 额度用完时换 Opus 最高，换之前把交接摘要写进 PROGRESS.md
- executor：Opus
- Ultracode 默认关；只有量大、能并行拆分时才建议开，做完提醒我关

## 新对话
每完成一个 Phase，或对话变长、开始反复出错时：先把交接摘要写进 PROGRESS.md，再提醒我开新对话。新对话开始时先读 PROGRESS.md，并提醒我输入 /rc 开启手机远程连接。

## 两台电脑
我有 Windows 11 和 Mac。项目在哪台做写进 PROGRESS.md；两台都用时，换电脑前提醒我提交并推送，另一台先拉取；.env 每台各放一份，不进 git。Windows 上项目文件和大文件（仓库、工具链、缓存）一律放 F 盘，不放 C 盘；Claude Code 自己的设置文件夹和已安装的软件除外。

## 安全
API 密钥只放 .env，不写进任何文件或对话。

## 偏好
中文解释，保留必要英文术语；先说做什么，再说为什么；命令按当前电脑给（Windows 用 PowerShell，Mac 用终端），可直接复制。

## 本项目补充
- 本项目没有硬件。「必须停下来问我」里的硬件操作，在这里对应真机和 Windows 上的操作：插线、在手机上点、停 / 重启 Windows 服务、在 Windows 上 git pull、Xcode 图形界面里的操作，都由我动手，导演给步骤
- 仓库是公开的（github.com/k086-cloud/clipbridge，分支 main）：每次 push 都先问我。本地 commit 由 executor 按功能分次做，导演审查
- 本机文件不进 git：`.claude/settings.local.json` 靠 .gitignore 的 `*.local.json` 排除；`.claude/agents/` 是项目共享配置，进 git
- 派 executor 子代理是常规做法，不用先问；Ultracode 仍默认关
- Windows 上仓库的本机路径不写进仓库里的任何文件
- 编译输出放仓库外（Xcode 默认的 DerivedData 就在仓库外）
- PROGRESS.md 里完成的任务压缩成一行，保持文件简短；任务需要换模型、调强度或开 Ultracode 时才在任务里写明

# 代码规则与技术约定

## 代码规则
- 键盘扩展不引入大型第三方库（内存上限约 50–70 MB，超了静默被杀）
- ATS 不全局关闭，只用 `NSAllowsLocalNetworking` 放行局域网 HTTP；其余网络请求仍受 ATS 保护
- 只做纯文本；图片 / 文件、历史持久化、mDNS、HTTPS、开机自启、托盘图标都是后续（候选见 PROGRESS.md）
- 按功能分多次有意义的 commit，不要一个大 commit
- 不要提交任何含 token、密钥的文件
- 改动涉及 API 时，同步更新本文件的"API 契约"和 windows-server/README.md
- 改动涉及 iOS 行为时，同步更新本文件的「各 target 实现要点」和根目录 README 的使用步骤

## 仓库结构（monorepo）
- `windows-server/` — Python 服务（FastAPI），包 `clipbridge_server/`
- `ios/` — Xcode 27 工程 `ClipBridge.xcodeproj`（JSON 格式 `project.xcproj`）+ 三个 target 目录 + 本地 Swift Package `ClipBridgeKit/`
- 远程仓库：github.com/k086-cloud/clipbridge（公开），分支 main

## Windows 端

### 模块
- `history.py` — 内存 deque 保留 history_size 条（默认 20），`clear()` 清空并返回条数；`ClipItem{id, content, timestamp(ISO 本地时区，精确到毫秒), source: "pc"|"phone"}`，id 为 uuid4 hex
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
- `DELETE /clip/history` — 0.3.0 起；清空内存历史，返回 204、无响应体；只清历史不动 monitor 的 last_seen，所以电脑剪贴板上现有的那条不会被重新记录，要等电脑复制新内容；日志只写清掉几条，不写内容；0.3.0 以前的服务端对它返回 405（路径存在、方法不对，和 token 对错无关）
- `POST /clip`，body `{"content": "..."}` — 写入电脑剪贴板，记为 source=phone，返回 201；content 为空返回 422；UTF-8 编码超 max_text_bytes（默认 102400 字节）返回 413；写剪贴板失败返回 503
- 除 /health 外都要 `Authorization: Bearer <token>`，否则 401
- 配对二维码内容：`clipbridge://pair?host=<ip>&port=<port>&token=<token>`

### 开发命令（在 windows-server/ 下）
- 建环境：`python -m venv .venv`，然后 `.venv\Scripts\pip install -r requirements.txt`（跑测试还需 `.venv\Scripts\pip install -r requirements-dev.txt`，含 pytest、httpx）
- 启动：`.venv\Scripts\python.exe -m clipbridge_server`
- 测试：`.venv\Scripts\python.exe -m pytest`（剪贴板用 FakeClipboard mock，不碰真实剪贴板）
- Mac 上也能跑测试（pyperclip 跨平台）：`python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt`，然后 `.venv/bin/python -m pytest`；真实剪贴板行为以 Windows 上的验收为准
- 改了 API 或防回环逻辑必须补测试，全部通过再提交

### 已知坑
- `api.py` 不能加 `from __future__ import annotations`，Annotated Query 引用闭包变量会解析失败
- 启动时会把当前剪贴板内容记为第一条 pc 记录（只在内存；剪贴板为空或超过 max_text_bytes 时不记录）
- 校园网常有 AP 隔离或分子网，手机连不上电脑时换家用路由或手机热点
- 防火墙：首次启动允许 Python 访问专用网络，或管理员执行 `netsh advfirewall firewall add rule name="ClipBridge 8765" dir=in action=allow protocol=TCP localport=8765`
- PowerShell 5.1 下中文乱码靠响应头 charset=utf-8 解决，不要去掉
- 改了服务端要在 Windows 上 `git pull` 后重启才生效

## iOS 端

### 实测结论（v0.1 各阶段真机验证，长期有效）
- 阶段 0 签名与 capability：免费 Personal Team（Team ID `L24ST657GM`）+ Xcode 27.2 下 **App Groups 和 Keychain Sharing 都能用**，codesign 实测 .app 和两个 .appex 都带 `application-groups` 和 `keychain-access-groups`；Bundle ID 注册判重不区分大小写（小写注册失败后用了大写）；Xcode 27.2 只能给 iOS 17+ 真机装调试包，部署目标 17.6；工程文件是 JSON 的 `.xcproj`
- 阶段 1 ClipBridgeKit：本地包静态链接到三个 target；测试在 Mac 上用 `swift test` 跑（网络用 MockURLProtocol，Keychain 用内存实现）
- 阶段 2 主 App：扫码配对、确认页、测试连接两行全绿、401 / 连不上的提示、系统相机扫 clipbridge:// 二维码弹「Open in ClipBridge」直达确认页、AppIdentifierPrefix 展开、`live()` 和 Keychain 写入都正常。**「本地网络」弹窗没测到**：手机和电脑在不同子网、流量经路由转发时，iOS 不把它当本地网络（TN3179 的定义），不弹窗、不受限、设置里也没有条目
- 阶段 3 键盘：没开「允许完全访问」时能读 App Group 的地址并提示去开；开了之后拉取 5 条卡片、点卡片插入全文、刷新、发送剪贴板（弹「允许粘贴」）都正常
- 阶段 4 共享扩展：Safari 选中文字 → 分享 → ClipBridge，电脑 Ctrl+V 得到干净正文。第一版把 Safari 给的 bplist 归档当 UTF-16 解成「扰汩猿」乱码发了出去，已修（见「各 target 实现要点」）
- 验收环境 iPhone 17 Pro Max，iOS 26.6.1；无害的控制台日志：首次访问 App Group UserDefaults 的 CFPrefs「detaching from cfprefsd」、相机关闭时的 FigCaptureSourceRemote err=-17281

### 每 7 天重装（免费账号）
- 描述文件 7 天过期（本轮到期日见 PROGRESS.md「定期事项」），到期后 App、键盘、共享扩展一起打不开。连上 iPhone 覆盖安装即可（Xcode 运行目标选这台 iPhone 按 ⌘R，或用下面的命令行）；键盘的启用状态和「允许完全访问」开关保留，配对信息保留（App Group 和 Keychain 都不动）
- 命令行装机（2026-11-05 实测可用，代替 Xcode ⌘R）：iPhone 数据线连 Mac 并解锁，在仓库根目录依次执行
  - 编译：`xcodebuild -project ios/ClipBridge.xcodeproj -scheme ClipBridge -configuration Debug -destination 'id=<UDID>' -allowProvisioningUpdates build`
  - 安装：`xcrun devicectl device install app --device <UDID> ~/Library/Developer/Xcode/DerivedData/ClipBridge-*/Build/Products/Debug-iphoneos/ClipBridge.app`
  - 启动：`xcrun devicectl device process launch --device <UDID> --terminate-existing com.charleschen.ClipBridge`
  - 查到期日：`security cms -D -i ~/Library/Developer/Xcode/DerivedData/ClipBridge-*/Build/Products/Debug-iphoneos/ClipBridge.app/embedded.mobileprovision | plutil -extract ExpirationDate raw -o - -`（UTC）
  - `<UDID>` 从 `xcrun devicectl list devices` 看；用 UDID 不用设备名（设备名可能和 Mac 本机名撞，xctrace 实测报 ambiguous）
- 提前重装不会顺延：描述文件没到期前重装，签进包里的还是原来那份（2026-11-05 重装后 embedded.mobileprovision 仍是 11-03 签发，到期日没变），Xcode 只在快过期或已过期时才重新签发。到期后命令行的 `-allowProvisioningUpdates` 能不能自动续签还没验证，不行就退回 Xcode ⌘R
- 其他限制：每周最多注册 10 个 App ID（本项目占 3 个，**Bundle ID 绝不改名**）、3 台设备、每台 3 个 App（扩展可能计数，手机上别装其他免费签名的 App）；没有 TestFlight

### Target 与 Bundle ID（已注册到 Personal Team，绝不要改名）
- `ClipBridge`（主 App，SwiftUI）= `com.charleschen.ClipBridge`
- `ClipBridgeKeyboard`（Custom Keyboard Extension）= `com.charleschen.ClipBridge.ClipBridgeKeyboard`
- `ClipBridgeShare`（Share Extension）= `com.charleschen.ClipBridge.ClipBridgeShare`
- 只支持 iPhone（`TARGETED_DEVICE_FAMILY=1`，Designed for iPad 的 Mac/Vision 目标已关）；主 App 锁竖屏

### Capability（三个 target 都有，已实测签进包）
- App Groups `group.com.charleschen.ClipBridge`
- Keychain Sharing `com.charleschen.clipbridge.shared`，运行时完整组名 `L24ST657GM.com.charleschen.clipbridge.shared`，前缀从各 target Info.plist 的 `AppIdentifierPrefix = $(AppIdentifierPrefix)` 读
- 检查命令：`codesign -d --entitlements - --xml ~/Library/Developer/Xcode/DerivedData/ClipBridge-*/Build/Products/Debug-iphoneos/ClipBridge.app`（两个扩展在 `PlugIns/*.appex`）；描述文件 `security cms -D -i <bundle>/embedded.mobileprovision`

### 配对信息存储
- host/port 存 App Group 的 UserDefaults（键盘没开「允许完全访问」时仍可只读共享容器，真机已证实），token 存共享 Keychain：kSecClassGenericPassword，service `com.charleschen.clipbridge.pairing`，account `token`，`AfterFirstUnlockThisDeviceOnly`，先删后加
- 封装在 `ClipBridgeKit.SharedPairingStore`：`load()` 返回 `PairingState`（notPaired / paired / tokenUnavailable(reason)），`save` 和 `clear` 都先动 Keychain 再动地址；真机用 `SharedPairingStore.live()`（Info.plist 缺 AppIdentifierPrefix 或没有 App Group entitlement 时返回 nil，不静默降级），测试和预览用 `.inMemory()`

### ClipBridgeKit（`ios/ClipBridgeKit`，本地 Swift Package）
- `swift-tools-version: 5.9`（Swift 5 语言模式，别升到 6——App target 默认 MainActor 隔离，跨模块会报一堆并发错误）；platforms iOS 17 / macOS 14（macOS 只为了 `swift test`）；只 import Foundation 和 Security，禁止 UIKit
- 模块：`PairingInfo`/`PairingEndpoint`、`PairingURLParser`、`ClipItem`/`HistoryResponse`/`HealthResponse`/`ClipBridgeJSON`、`ClipBridgeError`（+ `ClipBridgeMessages` 中文文案）、`ClipBridgeClient`、`PairingStore`（协议 + `SharedPairingStore`、`UserDefaultsEndpointStore`、`InMemory*`）、`KeychainTokenStore`/`KeychainError`/`KeychainAccessGroup`、`SharedTextDecoder`、`ClipBridgeIdentifiers`
- 客户端约定：任何 2xx 算成功；`health()` 必须解出 `HealthResponse`（解不出 = 对面不是 ClipBridge）；`latest()` 走 `history?limit=1`，空数组 → nil，真 404 → `.notFound`（host 指错）；`recentHistory(preferredLimit: 5)` 收到 422 退化成 limit=1；`clearHistory()` 走 `DELETE /clip/history`，204 无响应体；405 一律映射成 `.serverOutdated`（已知接口上的 405 只会是服务端比接口老，提示用户去电脑上更新）；422 错误体是数组、其他是字符串（413 的 `payloadTooLarge(String)` 带服务端说明，里面有实际上限）；时间戳 ISO8601 带毫秒；发送前本地拦空内容和 UTF-8 超 102400 字节；`defaultSession` 整个进程共用（3 s / 5 s），别每次 `makeSession()`；`transport(.notConnectedToInternet)` 多半是本地网络被拒，`.appTransportSecurityRequiresSecureConnection` 是 ATS 没放行，`underlying(NSPOSIXErrorDomain, 1)` 是扩展沙盒禁网
- `PairingEndpoint.isValidHost`：含冒号必须是 IPv6 字面量（拦「IP:端口」），`%` 不收；值类型本身不校验，校验在边界（URL 解析、手动输入、存储读取）
- 测试：`cd ios/ClipBridgeKit && swift test`。改 API 契约、存储逻辑或解码规则必须补测试

### 各 target 实现要点
- 主 App（SwiftUI，`ios/ClipBridge/`）：`AppModel`（@Observable；配对状态、待确认配对、可取消的测试连接、清空电脑历史）。「电脑上的历史」分区只在已配对时出现：红色按钮 → `confirmationDialog`（挂在按钮上，外层已有解除配对的确认框和两个 alert；显式写「取消」按钮）→ `clearPCHistory()`；结果显示在按钮下方，和测试连接同一风格（转圈 / 绿色成功 / 红色原因 + 灯泡提示，提示复用 `AppModel.hint(for:port:)`，`.serverOutdated` 提示去电脑上 git pull 并重启）；用代数丢弃过时结果，配对 / 解除配对时清掉；成功后收起旧的连接测试结果（里面的「已记录 N 条」已过时）。测试连接 = /health 解析成功 → 这一行立即变绿 → history?limit=1；首次访问局域网时用 scenePhase 判断系统弹窗是否出现、用户是否作答，答完再试最后一次，4 秒没弹窗或总计 25 秒才报被拒。扫码用 AVCaptureMetadataOutput（VisionKit 要 A12+）；扫到的码在 sheet 关闭后（onDismiss）再交给 model，同一帧关一个 sheet 又开一个会被 SwiftUI 丢掉；扫码和 clipbridge:// 链接都先确认再保存；token 只显示头尾 4 位，「填入当前地址」不把 token 放进明文输入框
- 键盘（UIKit，`ios/ClipBridgeKeyboard/`）：出现时先看 `hasFullAccess`——没开 → 不碰网络和 Keychain，读 App Group 地址提示去开；开了 → `live()` → `recentHistory(preferredLimit: 5)` → 卡片（200 字预览、3 行）。地球键只在 `needsInputModeSwitchKey` 时显示；竖屏 280 / 横屏 190 pt（键盘跟随宿主方向）；状态行固定 20 pt（否则 UIStackView 让它吃掉全部高度，卡片区域被压成 0 pt 且不报错）；卡片是 UIControl，滚动视图重写 `touchesShouldCancel(in:)` 返回 true 才能按住拖动；隐藏的地球键宽度约束用 999 优先级；`UIPasteboard.string` 在 iOS 16+ 每次新内容都会弹「允许粘贴」，返回 nil 表示用户拒绝不是剪贴板为空；键盘消失时取消任务并复位界面；字体跟随动态字体但封顶
- 共享扩展（UIKit，`ios/ClipBridgeShare/`）：激活规则 `{NSExtensionActivationSupportsText: true}`。**取文字顺序** 先用 `loadFileRepresentation` 只看附件大小（超过 2 MB 直接拒，防止大文件撑爆扩展）→ `loadObject(ofClass: NSString.self)` → `loadItem(forTypeIdentifier: public.plain-text)`（iOS 27 SDK 标 deprecated 但可用，是唯一会把老式注册的 NSString 还原出来的接口）→ `loadObject(NSAttributedString)`（它会把归档字节当文本解，所以 `SharedTextDecoder.nonEmpty` 也拒收 `bplist0` 开头或含 NUL 的字符串）→ 原始 Data 经 `SharedTextDecoder` 校验（合法 UTF-8 或带 BOM 的 UTF-16、不含 NUL；bplist 只按 NSKeyedUnarchiver 解 NSAttributedString/NSString；二进制一律不当文本）→ `attributedContentText`；全失败报错不发送，错误里带 `registeredTypeIdentifiers`，控制台打印每个附件的类型和最终走到哪一步。POST 成功后 0.8 秒 `completeRequest`（调用后进程立即回收）；失败显示原因（含电脑地址），网络 / 503 类可「重试」，「关闭」走 `cancelRequest(withError:)`；iPhone 上是整屏 sheet，用户下拉关闭走 `viewDidDisappear` → 取消请求 + `cancelRequest(NSUserCancelledError)`，`finished` 标记保证 context 只结束一次；超时 8 s / 12 s；分享面板显示名 `CFBundleDisplayName = ClipBridge`

### Info.plist（已加）
- 三个 target：`AppIdentifierPrefix = $(AppIdentifierPrefix)`、`NSAppTransportSecurity → NSAllowsLocalNetworking = YES`（ATS 对扩展也生效，不能只加主 App）
- 主 App `ios/ClipBridge/Info.plist`（与生成的 Info.plist 合并；工程里用 membership-exceptions 把它排除出资源）：`NSLocalNetworkUsageDescription`（只放主 App，不放扩展）、`NSCameraUsageDescription`、URL scheme `clipbridge`
- 键盘：`RequestsOpenAccess = YES`（否则没有「允许完全访问」开关，也没网络）、`PrimaryLanguage = zh-Hans`、`IsASCIICapable = true`
- 共享扩展：`NSExtensionActivationRule` 字典、`NSExtensionPrincipalClass = $(PRODUCT_MODULE_NAME).ShareViewController`（模板的 SLComposeServiceViewController 和 storyboard 已删）

### 工程与工具
- 工程文件是 JSON 格式 `ios/ClipBridge.xcodeproj/project.xcproj`（不是 pbxproj），只有 Xcode 27+ 能打开。改构建设置、target、包依赖优先用 Xcode 27 自带的 `xcrun xcodeproj`（`setting` / `target` / `group` / `pkg` 子命令，`xcrun xcodeproj pkg list -P ios/ClipBridge.xcodeproj` 可看包链接），手改 JSON 前先看清格式
- 验证构建：`xcodebuild -project ios/ClipBridge.xcodeproj -scheme ClipBridge -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`；真机 SDK 用 `-sdk iphoneos -destination 'generic/platform=iOS' -allowProvisioningUpdates`
- 三个 target 都是 Swift 5 语言模式 + Approachable Concurrency；只有主 App target 默认 MainActor 隔离，两个扩展默认 nonisolated。Kit 的 PairingStore/EndpointStore/TokenStore 都继承 Sendable，App 侧自写实现要么是只含 let 的 struct，要么是带锁的 `final class … @unchecked Sendable`
- ClipBridgeKit 已作为本地包静态链接到三个 target（`ClipBridgeKit.o` 各链一份）；ios/ClipBridgeKit 必须和 ClipBridge.xcodeproj 同级，不能移进三个同步文件夹里；三个 target 目录是同步文件夹，新文件自动编进去
- 分工：装机可以由 Claude 用命令行做（见「每 7 天重装」，前提是手机插线、解锁）；新建 target、capability、Package 链接仍在 Xcode 图形界面里由人做；代码、Info.plist、工程构建设置由 Claude 改文件后用 xcodebuild 验证
- 从 Mac 抓 iPhone 日志（2026-11-05 实测）：手机插线、解锁，不用 sudo；只录开始以后的日志，先开录再操作手机
  - 录制：`xcrun xctrace record --template Logging --device <UDID> --all-processes --time-limit 1m --no-prompt --output <仓库外的目录>/x.trace`
  - 导出：`xcrun xctrace export --input <仓库外的目录>/x.trace --xpath '/trace-toc/run[@number="1"]/data/table[@schema="os-log"]' --output <仓库外的目录>/x.xml`，再 grep
  - 录的是整台手机所有 App 的日志：放仓库外，用完就删。时间别太长：5 分钟的录制收尾保存花了约 9 分钟，1 分钟左右够用
  - 系统 subsystem 的 info 级录得到，本项目 `com.charleschen.ClipBridge` 的 info 级一条没录到（键盘 Keychain probe 那行没出现，而系统日志证明那段代码执行了）。要用 xctrace 看自己的日志，得用 `.notice` 或更高级别
  - 不用的办法：`log collect --device` 要 sudo（zsh 里裸写 `log` 是内建命令，要写 `/usr/bin/log`）；`xcrun devicectl device sysdiagnose` 实测报错
- Xcode 27 新建工程默认创建嵌套 git 仓库，建工程时取消勾选（仓库里不应有 ios/.git）

### 已知坑
- 本地网络权限按 App 记录、扩展继承；必须由主 App 前台先触发（「测试连接」）；iOS 18 起没有 NSLocalNetworkUsageDescription 弹窗不出现；被拒表现为 URLError -1009；只有直连同一 Wi-Fi 子网才算「本地」，经路由转发的流量不弹窗也不受限；模拟器不支持，只能真机测
- 键盘没开完全访问时禁一切网络；Keychain 能否读 Apple 没写，以 `hasFullAccess` 为准，不用 Keychain 失败推断
- 内存：键盘约 50–70 MB、共享扩展约 120 MB，超了静默被杀；键盘只显示截断文本、不缓存
- 分享面板给的「纯文本」可能是 bplist 归档；任何从 NSItemProvider / 剪贴板拿到的 Data 都要过 `SharedTextDecoder`，解不开就报错，绝不原样发送
- token 和剪贴板内容在局域网内明文传输，只在家用 Wi-Fi 或手机热点下用；怀疑泄露就删 config.json 重启重配
