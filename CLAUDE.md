# ClipBridge

Windows 电脑 ↔ iPhone 剪贴板同步。Windows 端 Python 服务 + iOS 键盘扩展（电脑→手机）+ iOS 共享扩展（手机→电脑）。
当前状态：Windows 端 v0.1（纯文本）已完成；iOS 部分尚未开始，将在 Mac 上开发。

## 仓库结构（monorepo）
- `windows-server/` — Python 服务（FastAPI），包 `clipbridge_server/`
- `ios/` — iOS App + 扩展（预留，尚未创建）
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
- `GET /health` — 免鉴权
- `GET /clip/latest` — 最新一条，空则 404
- `GET /clip/history?limit=N` — N 为 1..history_size（默认 20，超范围返回 422），省略时取全部；最新在前；响应为 `{"items": [...]}`
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

## iOS 端计划（尚未开始）
- SwiftUI 主 App（iOS 16+）：扫码配对 / 手动输入作为备用，"测试连接"按钮，引导用户开启键盘和"允许完全访问"
- 键盘扩展：出现时拉 `/clip/history?limit=5` 显示卡片，点卡片用 `insertText` 插入；刷新按钮、"发送到电脑"按钮；必须有地球键；内存限制严，不引入大型第三方库
- 共享扩展：选中文字 → 分享 → POST /clip（键盘跑通后再做）
- 主 App 与扩展通过 App Group 共享 host/port/token（token 尽量放共享 Keychain）。先用免费 Apple ID（Personal Team）签名，若其不支持 App Group 要先明确说明并给替代方案
- ATS 用 NSAllowsLocalNetworking 放行局域网 HTTP，不要全局关闭
- 网络层封装成 `ClipBridgeClient`（async/await），主 App 和扩展共用，并给它和配对 URL 解析写单元测试

## 约定
- 第一版只做纯文本；图片/文件、历史持久化、mDNS、HTTPS、开机自启、托盘图标都是后续
- 按功能分多次有意义的 commit，不要一个大 commit
- 不要提交任何含 token、密钥的文件
- 改动涉及 API 时，同步更新本文件的"API 契约"和 windows-server/README.md
