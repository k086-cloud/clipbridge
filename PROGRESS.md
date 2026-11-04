# ClipBridge 进度

本文件是项目的总台账：目标、阶段、任务、状态和决策记录都以这里为准。协作规则和代码规则见 CLAUDE.md，使用步骤见 README.md。

本项目由两个 Claude 对话协作：「导演」（claude.ai 中的对话）负责规划和审查，「执行」（VS Code 里的 Claude Code）负责改代码并维护本文件。

任务标注说明：每个任务写难度（高 / 中 / 低）和验收标准；模型默认 Opus、高思考强度，Ultracode 默认关，需要变化时才在任务里写明。

## 电脑分工
- Mac：主要开发都在这台，包括 iOS 和 Windows 服务的代码，以及 Xcode 编译、真机安装
- Windows：只运行服务、做最终测试。服务端代码改动后，测试前在 Windows 上 `git pull` 并重启服务
- 服务端测试在 Mac 上也能跑（pyperclip 跨平台，测试用 FakeClipboard）；真实剪贴板行为以 Windows 上的验收为准
- 换电脑前：当前这台先 commit 并 push（push 前要维护者确认），另一台开工前先 `git pull`
- `.env` 每台各放一份，不进 git

## 目标
在 Windows 电脑和 iPhone 之间同步纯文本剪贴板。两个方向都在 iPhone 上操作，电脑照常复制、粘贴。
- 电脑 → 手机：iPhone 上切到 ClipBridge 键盘，点卡片插入电脑最近复制的内容
- 手机 → 电脑：iPhone 上选中文字 → 分享 → ClipBridge，电脑直接 Ctrl+V

架构：Windows 端 Python 服务（FastAPI）+ iOS 主 App（配对、测试连接）+ 键盘扩展 + 共享扩展，三个 iOS target 共用本地包 ClipBridgeKit。

## 当前状态
- v0.1.0 已于 2026-11-03 发布（标签 `v0.1.0`，仓库公开），双向主功能都在真机上验收通过
- Windows 服务版本：仓库里 0.3.0（加了清空历史，未 push），Windows 上运行的仍是 0.2.0
- 进行中：v0.2「清空历史」（见「任务」）

## 阶段（v0.1 全部完成）
- [x] Windows v0.1：Python 服务（纯文本）
- [x] iOS 0：Xcode 工程、签名、capability
- [x] iOS 1：ClipBridgeKit（网络层、配对解析、存储）
- [x] iOS 2：主 App（扫码 / 手动配对、测试连接）
- [x] iOS 3：键盘扩展（电脑 → 手机）
- [x] iOS 4：共享扩展（手机 → 电脑）
- [x] iOS 5：收尾（README、CLAUDE.md 定稿）

## 任务

### 进行中：v0.2 清空历史
- 难度：中
- 范围：服务端 `DELETE /clip/history`（要 token，成功 204、清空内存历史，token 错 401，版本 0.2.0 → 0.3.0）；`ClipBridgeClient.clearHistory()`（旧服务端返回 405 → 提示去更新）；主 App 带确认框的「清空电脑上的历史」按钮，成功 / 失败都有提示；键盘这次不加
- 验收标准：
  1. 服务端新测试通过：带对的 token 调 DELETE 返回 204，之后 `GET /clip/history` 为空；token 不对返回 401
  2. ClipBridgeKit 的 `swift test` 全部通过（clearHistory 覆盖 204、401、服务端太旧、连不上）
  3. 真机（Windows 上 pull 并重启服务后）：主 App 点按钮 → 确认 → 提示成功，键盘刷新后没有卡片、空状态显示正常；点取消不清空；清空后电脑不复制新内容，键盘就一直是空的，复制一条后键盘里只出现这一条；停掉服务时点按钮，显示连接失败的提示；Windows 还没更新时点按钮，提示去更新电脑上的服务
  4. 同一次真机测试顺便做：重装续期（这次试命令行 xcodebuild + devicectl，不行退回 Xcode ⌘R；更新「定期事项」的到期日），以及待补测第 2、4、5、6 项
- 进度：代码 + 文档 ✅（服务端 86 个测试、Kit 89 个测试全过；模拟器和 iphoneos 签名编译通过）→ push（等确认）→ 真机测试（未开始）

### 待补测（v0.1 真机补测，不影响日常使用；都在 Mac + iPhone 上做，Windows 服务开着）
1. **「本地网络」权限弹窗和拒绝后的 -1009 提示**
   - 难度：中（要搭出同一子网的环境，例如电脑连手机热点）
   - 验收标准：主 App 首次「测试连接」弹出本地网络权限弹窗；拒绝后显示本地网络被拒的提示（URLError -1009）；到设置里重新允许后能连通，允许后键盘和共享扩展也能连通
2. **共享扩展反向激活规则**
   - 难度：低
   - 验收标准：分享网址或图片时，分享面板里不出现 ClipBridge；分享选中文字时出现
3. **键盘内存**
   - 难度：中
   - 验收标准：Xcode → Debug → Attach to Process by Name「ClipBridgeKeyboard」，拉取 5 条卡片，反复刷新 20 次，内存不持续上涨；峰值记下来，超过 40 MB 再查原因；设置 → 隐私与安全性 → 分析与改进 → 分析数据 里没有 ClipBridgeKeyboard 的 JetsamEvent
4. **键盘和共享扩展的异常提示**
   - 难度：低
   - 验收标准：停掉服务、解除配对、用错 token 三种情况下，键盘和共享扩展各自显示对应提示，不崩溃、不卡住
5. **主 App「解除配对」按钮**
   - 难度：低
   - 验收标准：点击后回到未配对状态；键盘提示未配对；重新扫码配对后一切正常
6. **键盘没开「允许完全访问」时读共享 Keychain 的结果**
   - 难度：低
   - 验收标准：关掉完全访问后打开键盘，控制台「Keychain probe without Full Access」那一行的输出（readable / no item / failed 及错误），结果写进 CLAUDE.md 的 iOS「已知坑」
7. **扩展是否计入免费账号「每台 3 个 App」的限额**（暂缓）
   - 暂缓原因：测它要新建 App，会占用免费账号每 7 天 10 个 App ID 的额度，等真有别的 App 要装时再测
   - 难度：低
   - 验收标准：得出明确结论（例如再装一个免费签名的 App 时是否被拒），写进 CLAUDE.md 的「每 7 天重装（免费账号）」一节

### 已完成
- 2026-11-04 切换到导演 / 执行分工：CLAUDE.md 改为协作规则 + 代码规则，进度移到 PROGRESS.md，导演审查通过
- 2026-11-03 发布 v0.1.0：Windows 服务 + iOS 主 App / 键盘 / 共享扩展，双向真机验收通过

## 定期事项
- 免费账号的描述文件 7 天过期，本轮到期日 **2026-11-10**。到期后 App、键盘、共享扩展一起打不开：连上 iPhone，在 Xcode 里 ⌘R 覆盖安装即可，配对信息和键盘设置都保留。每次重装后到期日顺延 7 天，重装后更新这里的日期

## 待排期（v0.2 及以后，只是候选，顺序未定）
- 跨网络使用：手机和电脑不在同一网络时也能用。现在 token 和内容是明文 HTTP，只适合局域网，要和 HTTPS 一起解决
- HTTPS（自签证书 + 指纹 pin，指纹放进配对码）；一次性配对码代替 URL 里的 token
- iPad 支持；Mac 端只做 Mac ↔ Windows（Mac ↔ iPhone 用系统自带的通用剪贴板）
- 图片 / 文件；历史持久化；mDNS 发现；开机自启；托盘图标
- 键盘：长按连删、回车键；共享扩展：分享网址时也出现
- README 顶部加键盘拉取电脑剪贴板的截图或 GIF

## 决策记录（新的在上）
- 2026-11-04：v0.2 第一个任务做「清空历史」。原因：改动小，适合先把新流程跑通；真机验收时顺便重装续期、做低难度补测
- 2026-11-04：主要开发集中在 Mac（iOS 和服务端代码都在 Mac 上写），Windows 只运行服务和做最终测试；换电脑前 commit + push，另一台先 pull。原因：iOS 只能在 Mac 上编译，开发集中在一台电脑上切换更少；服务要读 Windows 剪贴板，所以仍在 Windows 上运行
- 2026-11-04：计划、进度、决策放仓库根目录 PROGRESS.md，由执行方（Claude Code）维护、导演审查；CLAUDE.md 放协作规则和代码规则；claude.ai 的 Project 指令只放导演规则。原因：同一信息只留一处，执行的一方能直接读写
- 2026-11-03：仓库改为公开。已确认 git 历史里没有 token 和 config.json
- 2026-11-03：Bundle ID 用大写 `com.charleschen.ClipBridge`，绝不改名。小写版注册失败（Apple 判重不区分大小写，Xcode 已先注册了大写版）；免费账号每 7 天只能注册 10 个 App ID
- 2026-11-03：最低部署 iOS 17.6（原计划 16）。Xcode 27.2 只能给 iOS 17+ 真机装调试包，部署目标下拉的最低值是 17.6
- 2026-11-03：配对信息 host/port 存 App Group，token 存共享 Keychain。实测免费账号 + Xcode 27.2 支持 App Group；键盘没开完全访问时也能读到地址并提示去开；token 是凭据，放 Keychain
- v0.1 规划时：ATS 只用 `NSAllowsLocalNetworking` 放行局域网 HTTP，不全局关闭。其余网络请求仍受 ATS 保护
- v0.1 规划时：v0.1 只做纯文本；图片 / 文件、历史持久化、mDNS、HTTPS 等放到后续
- v0.1 规划时：先用免费 Apple ID（Personal Team）签名。代价：每 7 天重装；限 3 台设备、每台 3 个 App；没有 TestFlight
