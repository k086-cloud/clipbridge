# ClipBridge 进度

本文件是项目的总台账：目标、阶段、任务、状态和决策记录都以这里为准。协作规则和代码规则见 CLAUDE.md，使用步骤见 README.md。

协作方式（2026-11-06 起）：导演在 claude.ai 的项目对话里；Claude Code 负责规划和执行，先说计划、维护者确认后再写代码，每个任务结束时输出「给导演的汇报」。真机和 Windows 上的操作由维护者动手，Claude Code 给步骤。

任务标注：难度（高 / 中 / 低）和验收标准必写；模型和强度默认不写（固定 Opus 高），要切 Fable 或调强度时才写；Ultracode 默认关，要开时才写。

## 电脑分工
- Mac：开发都在这台（iOS 和服务端代码、Xcode 编译、真机安装）。服务端测试在 Mac 上也能跑（pyperclip 跨平台，测试用 FakeClipboard）
- Windows：只跑服务做联调，真实剪贴板行为以这台为准。服务端代码改了之后，先在 Windows 上 `git pull` 再重启服务
- 换电脑前：当前这台先 commit 并 push（push 前要维护者确认），另一台先 `git pull`；`.env` 每台各放一份，不进 git

## 目标
自己用 + 简历，不做商业化。在 Windows 电脑和 iPhone 之间同步纯文本剪贴板，两个方向都在 iPhone 上操作，电脑照常复制、粘贴：
- 电脑 → 手机：iPhone 上切到 ClipBridge 键盘，点卡片插入电脑最近复制的内容
- 手机 → 电脑：iPhone 上选中文字 → 分享 → ClipBridge，电脑上直接 Ctrl+V

架构：Windows 端 Python 服务（FastAPI）+ iOS 主 App（配对、测试连接、清空电脑历史）+ 键盘扩展 + 共享扩展，三个 iOS target 共用本地包 ClipBridgeKit。

## 当前状态
- 功能开发已停（2026-11-06）：停在 v0.1.0 + v0.2 清空历史（服务 0.3.0）+ Phase 2 三条小修，全部在真机上验收通过。之后只做维护（续签）和简历材料
- Phase 3（iPad + 键盘回车键）已取消。做了一半的 iPad 改动存在本地分支 `wip/ipad-phase3`：没有编译验证，也没有审查，不合并
- 本地 main 比 origin/main 多几个文档提交，还没 push（以 `git status -sb` 为准）

## 交接摘要（2026-11-06，换成 claude.ai 导演时写）
- 新的协作方式见 CLAUDE.md「协作规则」。原来的导演会话 + executor 子代理不再用；`.claude/agents/executor.md` 还在仓库里，删不删等维护者定
- 描述文件 2026-11-10 06:11 UTC 到期，到期后 App、键盘、共享扩展一起打不开。「每周自动续签」要在这之前跑通一次
- 真机测试经验：先在 Mac 上 `curl http://<电脑 IP>:8765/health`。Windows 服务连得上时，不需要在电脑旁操作的项都能先验。看手机日志用 xctrace，本项目自己的日志要 `.notice` 以上才录得到（见 CLAUDE.md「工程与工具」）

## 阶段
- [x] v0.1（2026-11-03 发布 v0.1.0）：Windows 服务、Xcode 工程与 capability、ClipBridgeKit、主 App、键盘扩展、共享扩展、文档
- [x] Phase 1（2026-11-05）：v0.2 清空历史
- [x] Phase 2（2026-11-06）：三条小修
- [ ] ~~Phase 3：iPad + 键盘回车键~~（2026-11-06 取消）

## 任务

### 待做
- **每周自动续签**
  - 难度：中
  - 验收标准：一条命令能在 Mac 上重新签名，并把 ClipBridge（含键盘和共享扩展）装到 iPhone，配对信息和键盘设置不丢；定时任务每天检查，距上次成功满 5 天就自动跑，错过会补跑，失败时 Mac 弹通知；2026-11-10（当前签名过期）前在真机上跑通一次
  - 注意：免费账号能不能用命令行续签，网上说法不一，要先手动验证；不准改 Bundle ID。已知 2026-11-05 实测：描述文件没到期时重装不会顺延，Xcode 只在快过期或已过期时才重新签发，所以「满 5 天就跑」时能不能拿到新的描述文件也要验证。命令行装机步骤见「定期事项」；手机要插线并解锁
- **简历材料**
  - 难度：低
  - 验收标准：根据代码列出可以写进简历的技术亮点和具体数字，交给导演定稿英文描述；README 顶部的演示截图或 GIF 可选

### 可选补测（不阻塞；都在 Mac + iPhone 上做，Windows 服务开着）
原补测 2（共享扩展反向激活规则）、4（键盘和共享扩展的异常提示，即故障演练）、5、6 已在 2026-11-05 做完，编号保留。
- 补测 1「本地网络」权限弹窗和拒绝后的 -1009 提示（难度：中，要同一子网的环境，例如电脑连手机热点）。验收：主 App 首次「测试连接」时弹窗；拒绝后显示本地网络被拒的提示；到设置里重新允许后，主 App、键盘、共享扩展都能连通
- 补测 3 键盘内存（难度：中）。验收：Xcode → Debug → Attach to Process by Name「ClipBridgeKeyboard」，拉取 5 条卡片、反复刷新 20 次，内存不持续上涨，记下峰值（超过 40 MB 再查原因）；设置 → 隐私与安全性 → 分析与改进 → 分析数据里没有 ClipBridgeKeyboard 的 JetsamEvent
- 补测 7 扩展是否计入免费账号「每台 3 个 App」的限额（难度：低；暂缓，因为要新建 App，会占每 7 天 10 个 App ID 的额度）。验收：得出明确结论，写进 CLAUDE.md「每 7 天重装（免费账号）」

### 已完成
- 2026-11-06 Phase 2 三条小修：解除配对确认框补「取消」、键盘空状态文案、删掉键盘 Keychain probe；`swift test` 89 个全过，真机通过
- 2026-11-05 Phase 1 v0.2 清空历史：服务 0.3.0 `DELETE /clip/history`、Kit `clearHistory()`、主 App 清空按钮；真机全过，顺带做完补测 2、4、5、6
- 2026-11-05 切换到 Claude Code 导演会话 + executor 子代理（2026-11-06 换成 claude.ai 导演）
- 2026-11-04 切换到导演 / 执行分工，进度移到 PROGRESS.md
- 2026-11-03 发布 v0.1.0：Windows 服务 + iOS 主 App / 键盘 / 共享扩展，双向真机验收通过

## 定期事项
- 免费账号的描述文件 7 天过期，本轮到期 **2026-11-10 06:11 UTC（美东 01:11）**。到期后三个 target 一起打不开，重装即可，配对信息和键盘设置都保留。到期前重装不会顺延
- 命令行装机（2026-11-05 实测可用，代替 ⌘R）：手机插线解锁 → `xcodebuild -project ios/ClipBridge.xcodeproj -scheme ClipBridge -configuration Debug -destination 'id=<UDID>' -allowProvisioningUpdates build` → `xcrun devicectl device install app --device <UDID> <DerivedData>/Build/Products/Debug-iphoneos/ClipBridge.app` → `xcrun devicectl device process launch --device <UDID> --terminate-existing com.charleschen.ClipBridge`（用 UDID，不用设备名，见 CLAUDE.md）。查到期日：`security cms -D -i <ClipBridge.app>/embedded.mobileprovision | plutil -extract ExpirationDate raw -o - -`，重装后更新这里的日期

## 想法（只记下来，不做）
- 一个手势同步：App Intents + 轻点背面
- iPad 和电脑互传（2026-11-06 加入后当天撤回；半成品在 `wip/ipad-phase3`）
- Mac → Windows（菜单栏 App，或 `pbpaste` + POST）
- 给别人用（Windows 打包成 exe、付费开发者账号或别人自己编译、面向非开发者的 README）
- 跨网络使用、HTTPS（自签证书 + 指纹 pin）、一次性配对码
- 图片 / 文件、历史持久化、mDNS 发现、开机自启、托盘图标
- 键盘：长按连删、回车键；共享扩展：分享网址时也出现

## 建议
- 配对 token 在 2026-11-05 的导演对话里出现过一次（服务启动横幅被整段贴出）。服务只在局域网开，风险低；介意的话在 Windows 上删掉 config.json、重启服务、手机重新扫码，就能换新 token

## 决策记录（新的在上）
- 2026-11-06：协作方式换成 claude.ai 项目对话里的导演 + Claude Code 负责规划和执行（先说计划、确认后再写代码），不再用 Claude Code 里的导演会话 + executor 子代理。规则见 CLAUDE.md「协作规则」
- 2026-11-06：目标定为「自己用 + 简历」，不做商业化。原因：同类 App 已经有不少，热度都低
- 2026-11-06：功能开发停止。维护者原定「停在 v0.1.0」，因为 v0.2 清空历史和 Phase 2 已经做完并 push，确认改为停在现在，已做的不回滚。「一个手势同步」（App Intents + 轻点背面）只记为想法；同一天早些时候加入的 iPad、Mac → Windows、给别人用三个扩展目标撤回，也记为想法；Phase 3 取消，做了一半的 iPad 改动存在 `wip/ipad-phase3`
- 2026-11-06：仓库保持公开（简历要用），每次推送前先问维护者
- 2026-11-06：开发在 Mac 上做，Windows 只跑服务做联调（延续 2026-11-04 的决定）
- 2026-11-06：待补测项改为可选，不阻塞。剩下的是热点下本地网络弹窗（补测 1）、键盘内存（补测 3）、扩展是否占 App 限额（补测 7）；反向激活规则和故障演练已在 2026-11-05 做完
- 2026-11-06：确认框的「取消」接受 iOS 26 的系统行为，不改成 alert（真机上弹出框不显示 `.cancel` 按钮，点框外即取消）
- 2026-11-04：v0.2 第一个任务做「清空历史」：改动小，适合先跑通新流程
- 2026-11-04：计划、进度、决策放在仓库根目录 PROGRESS.md；CLAUDE.md 放协作规则和代码规则
- 2026-11-03：仓库改为公开。已确认 git 历史里没有 token 和 config.json
- 2026-11-03：Bundle ID 用大写 `com.charleschen.ClipBridge`，绝不改名（小写版注册失败；免费账号每 7 天只能注册 10 个 App ID）
- 2026-11-03：最低部署 iOS 17.6（Xcode 27.2 只能给 iOS 17+ 真机装调试包）
- 2026-11-03：host/port 存 App Group，token 存共享 Keychain（免费账号 + Xcode 27.2 实测支持）
- v0.1 规划时：ATS 只用 `NSAllowsLocalNetworking` 放行局域网 HTTP；只做纯文本；先用免费 Apple ID（Personal Team）签名，代价是每 7 天重装、限 3 台设备、每台 3 个 App、没有 TestFlight
