# ClipBridge 进度

本文件是项目的总台账：目标、阶段、任务、状态和决策记录都以这里为准。协作规则和代码规则见 CLAUDE.md，使用步骤见 README.md。

本项目在 Claude Code 里协作：导演会话（主会话）负责规划、派任务、审查并维护本文件；executor 子代理（`.claude/agents/executor.md`）负责改代码、自测、汇报。真机和 Windows 上的操作由维护者动手，导演给步骤。

任务标注说明：每个任务写内容、难度（高 / 中 / 低）和验收标准；导演用 Fable，executor 用 Opus，Ultracode 默认关，需要变化时才在任务里写明。

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
- v0.2「清空历史」已完成（Phase 1）：Windows 上运行的服务已更新到 0.3.0，真机全部验收通过
- 进行中：Phase 2 三条小修（2026-11-06 维护者确认）。Mac 上已改完并审查通过，等 11-10 到期重装时做真机验收（P2-4）

## 交接摘要（2026-11-05，Phase 1 结束时写）
- 协作方式：Claude Code 里的导演会话 + executor 子代理（`.claude/agents/executor.md`）。本会话中途才建 executor，所以派任务时用的是通用子代理加「先读 executor.md」；新会话里可以直接用 executor 类型
- Phase 1 的文档提交已在 2026-11-05 全部 push；以后每次 push 仍要先问维护者（仓库公开）
- 真机测试经验：开始前先在 Mac 上 `curl http://<电脑 IP>:8765/health` 确认 Windows 服务在跑（本次 B 第一次失败就是服务没开）；补测或调试要看手机日志时用 xctrace，录 1 分钟左右，本项目自己的日志要 `.notice` 以上才录得到
- 描述文件 2026-11-10 06:11 UTC 到期，到期后重装时顺便验证命令行能否自动续签（见「定期事项」）
- Phase 2（2026-11-06 确认）：「建议」区的三条小修，Mac 上已完成，真机验收 P2-4 的步骤写在「任务」→「Phase 2」；之后再从「待排期」选下一个功能

## 阶段（v0.1 全部完成）
- [x] Windows v0.1：Python 服务（纯文本）
- [x] iOS 0：Xcode 工程、签名、capability
- [x] iOS 1：ClipBridgeKit（网络层、配对解析、存储）
- [x] iOS 2：主 App（扫码 / 手动配对、测试连接）
- [x] iOS 3：键盘扩展（电脑 → 手机）
- [x] iOS 4：共享扩展（手机 → 电脑）
- [x] iOS 5：收尾（README、CLAUDE.md 定稿）

## 任务

### Phase 2：三条小修（2026-11-06 确认；Mac 上改完，真机验收等 11-10 到期重装）
P2-1 到 P2-3 在 Mac 上已完成（2026-11-06，导演审查通过；`swift test` 89 个用例全过，模拟器和 iphoneos 构建都过，未新增 warning），只差真机：
- P2-1 解除配对确认框补显式「取消」，和清空确认框一致（`bca57e4`）
- P2-2 键盘空状态文案改为「电脑上暂时没有记录。在电脑上复制一段文字，再点刷新。」（`961a903`）
- P2-3 删掉键盘 Keychain probe 和随之不用的 `Logger`，注释改为以真机结论为依据；CLAUDE.md 里的历史结论注明 probe 已删（`9ec3a6e`）
- **P2-4 真机验收**：待做，2026-11-10 06:11 UTC（美东 01:11）描述文件到期后、维护者在家时
  - 难度：低
  - 验收标准：下面每步都符合预期；续签结论写进 CLAUDE.md「每 7 天重装」；新到期日写进「定期事项」
  - 步骤（Windows 服务 0.3.0 开着；iPhone 插 Mac 并解锁）：
    1. Mac 上 `curl http://<电脑 IP>:8765/health`，有 JSON 返回再往下
    2. 用命令行装机（见「定期事项」）。看 `xcodebuild … -allowProvisioningUpdates` 能不能拿到新描述文件：装完查到期日，比 11-10 晚就算自动续签成功；编译报描述文件错误就退回 Xcode ⌘R，记下报错
    3. 打开 App → 「测试连接」两行全绿（配对信息保留）
    4. P2-1：点「解除配对」→ 弹框里有「取消」→ 点「取消」→ 配对还在，再测一次连接仍全绿（不要真的解除配对）
    5. P2-2：「清空电脑上的历史」→ 确认 → 在任意输入框切到 ClipBridge 键盘 → 显示新文案；电脑上复制一段新文字（清空不会重新记录电脑剪贴板上已有的那条）→ 键盘点刷新 → 出现卡片
    6. P2-3：设置 → 通用 → 键盘 → 键盘 → ClipBridge → 关掉「允许完全访问」→ 打开键盘 → 提示「要连接电脑 <IP> 需要「允许完全访问」…」；再打开完全访问 → 键盘正常拉到卡片
    7. 回归：Safari 选中文字 → 分享 → ClipBridge → 电脑 Ctrl+V 得到同样文字
  - 通过后：问维护者能否 push（本地比 origin/main 多的提交一起推）

### 待补测（v0.1 真机补测，不影响日常使用；都在 Mac + iPhone 上做，Windows 服务开着）
补测 2、4、5、6 已在 2026-11-05 完成（见「已完成」），编号保留不重排。
- **补测 1「本地网络」权限弹窗和拒绝后的 -1009 提示**
  - 难度：中（要搭出同一子网的环境，例如电脑连手机热点）
  - 验收标准：主 App 首次「测试连接」弹出本地网络权限弹窗；拒绝后显示本地网络被拒的提示（URLError -1009）；到设置里重新允许后能连通，允许后键盘和共享扩展也能连通
- **补测 3 键盘内存**
  - 难度：中
  - 验收标准：Xcode → Debug → Attach to Process by Name「ClipBridgeKeyboard」，拉取 5 条卡片，反复刷新 20 次，内存不持续上涨；峰值记下来，超过 40 MB 再查原因；设置 → 隐私与安全性 → 分析与改进 → 分析数据 里没有 ClipBridgeKeyboard 的 JetsamEvent
- **补测 7 扩展是否计入免费账号「每台 3 个 App」的限额**（暂缓）
  - 暂缓原因：测它要新建 App，会占用免费账号每 7 天 10 个 App ID 的额度，等真有别的 App 要装时再测
  - 难度：低
  - 验收标准：得出明确结论（例如再装一个免费签名的 App 时是否被拒），写进 CLAUDE.md 的「每 7 天重装（免费账号）」一节

### 已完成
- 2026-11-05 v0.2 清空历史（Phase 1）：服务端 0.3.0 `DELETE /clip/history`、Kit `clearHistory()`、主 App 带确认的清空按钮；真机 B 到 H 全过，顺带补测 2、4、5、6 全过，结论写进 CLAUDE.md（iOS「实测结论」「已知坑」「每 7 天重装」「工程与工具」）。准备任务：P1-1 找到用 xctrace 从 Mac 录手机日志（不用 sudo；能录到系统框架的 info 级，本项目自己的 info 级录不到），P1-2 按代码整理每步预期文案并实测 0.2.0 对 DELETE 回 405；P1-3 README 的 v0.1 验收日期改为 11-03
- 2026-11-05 切换到 Claude Code 导演会话 + executor 子代理：CLAUDE.md 的协作部分换成导演规则，新建 `.claude/agents/executor.md`
- 2026-11-04 切换到导演 / 执行分工：CLAUDE.md 改为协作规则 + 代码规则，进度移到 PROGRESS.md，导演审查通过
- 2026-11-03 发布 v0.1.0：Windows 服务 + iOS 主 App / 键盘 / 共享扩展，双向真机验收通过

## 定期事项
- 免费账号的描述文件 7 天过期，本轮到期 **2026-11-10 06:11 UTC（美东 01:11）**。到期后 App、键盘、共享扩展一起打不开，要重装；配对信息和键盘设置都保留
- **到期前重装不会顺延**：2026-11-05 用命令行重装，`embedded.mobileprovision` 仍是 11-03 签发、11-10 到期（Xcode 只在描述文件快过期或已过期时才重新签发）。所以要等到期后再重装，到时顺便试命令行能不能自己续签（`xcodebuild … -allowProvisioningUpdates` 能否拿到新描述文件），不行再用 Xcode ⌘R
- 命令行装机（2026-11-05 实测可用，代替 ⌘R）：手机插线解锁 → `xcodebuild -project ios/ClipBridge.xcodeproj -scheme ClipBridge -configuration Debug -destination 'id=<UDID>' -allowProvisioningUpdates build` → `xcrun devicectl device install app --device <UDID> <DerivedData>/Build/Products/Debug-iphoneos/ClipBridge.app` → `xcrun devicectl device process launch --device <UDID> --terminate-existing com.charleschen.ClipBridge`（用 UDID 不用设备名，见 CLAUDE.md）。装完查到期日：`security cms -D -i <ClipBridge.app>/embedded.mobileprovision | plutil -extract ExpirationDate raw -o - -`，重装后更新这里的日期

## 待排期（v0.2 及以后，只是候选，顺序未定）
- 跨网络使用：手机和电脑不在同一网络时也能用。现在 token 和内容是明文 HTTP，只适合局域网，要和 HTTPS 一起解决
- HTTPS（自签证书 + 指纹 pin，指纹放进配对码）；一次性配对码代替 URL 里的 token
- iPad 支持；Mac 端只做 Mac ↔ Windows（Mac ↔ iPhone 用系统自带的通用剪贴板）
- 图片 / 文件；历史持久化；mDNS 发现；开机自启；托盘图标
- 键盘：长按连删、回车键；共享扩展：分享网址时也出现
- README 顶部加键盘拉取电脑剪贴板的截图或 GIF

## 建议（超出目标的改进，等维护者确认后再排期）
- 配对 token 在 2026-11-05 的导演对话里出现过一次（服务启动横幅被整段贴出）。服务只在局域网开，风险低；介意的话在 Windows 上删掉 config.json、重启服务、手机重新扫码即可换新 token

## 决策记录（新的在上）
- 2026-11-05：改为 Claude Code 里的导演会话 + executor 子代理，不再用 claude.ai 的导演对话
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
