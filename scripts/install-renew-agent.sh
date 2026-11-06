#!/bin/bash
# 安装或卸载 ClipBridge 续签定时任务（当前用户的 launchd agent）。
#
# 用法（在 Mac 上执行）：
#   scripts/install-renew-agent.sh              安装：每天 20:00 检查一次，登录时也检查一次
#   scripts/install-renew-agent.sh --uninstall  卸载
#
# 每次检查跑 renew-ios.sh --if-due：距上次成功满 5 天才续签，失败时在 Mac 上弹通知。
# Mac 睡眠时错过的检查会在唤醒后补跑；关机时错过的在下次登录时补跑。
# 改检查时间：改下面的 HOUR，重新执行本脚本。

set -euo pipefail

LABEL="com.charleschen.clipbridge.renew"
HOUR=20
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SCRIPT="$(cd "$(dirname "$0")" && pwd)/renew-ios.sh"
STATE_DIR="$HOME/Library/Application Support/ClipBridge"
DOMAIN="gui/$(id -u)"

launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true

if [[ "${1:-}" == "--uninstall" ]]; then
  rm -f "$PLIST"
  echo "已卸载续签定时任务"
  exit 0
fi

chmod +x "$SCRIPT"
mkdir -p "$HOME/Library/LaunchAgents" "$STATE_DIR"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/caffeinate</string>
    <string>-i</string>
    <string>/bin/bash</string>
    <string>$SCRIPT</string>
    <string>--if-due</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key>
    <integer>$HOUR</integer>
    <key>Minute</key>
    <integer>0</integer>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$STATE_DIR/launchd.log</string>
  <key>StandardErrorPath</key>
  <string>$STATE_DIR/launchd.log</string>
</dict>
</plist>
EOF
plutil -lint "$PLIST" >/dev/null
launchctl bootstrap "$DOMAIN" "$PLIST"
echo "已安装续签定时任务：每天 $HOUR:00 检查一次，登录时也检查一次；距上次成功满 5 天就续签"
echo "日志和状态：$STATE_DIR"
