#!/bin/bash
# ClipBridge 续签：向 Apple 重新要免费账号的 7 天描述文件，编译并装到连着的 iPhone。
#
# 用法（在 Mac 上执行）：
#   scripts/renew-ios.sh            立即续签
#   scripts/renew-ios.sh --if-due   距上次成功满 5 天才续签（定时任务用这个）
#
# 前提：iPhone 用数据线连着 Mac（或已配好无线连接）并解锁过；Xcode → Settings → Accounts 里登录着 Apple ID。
# 原理：Xcode 只在本地没有可用的描述文件时才向 Apple 要新的（2026-11-06 实测），所以先把 ClipBridge 三个 target
#      的旧描述文件挪到备份目录，再用 -allowProvisioningUpdates 编译；编译失败就把旧的放回去。
# 覆盖安装不动 App Group 和 Keychain，配对信息和键盘设置都保留。Bundle ID 不能改。
# 状态和日志都在 ~/Library/Application Support/ClipBridge/（仓库外）。

set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
STATE_DIR="$HOME/Library/Application Support/ClipBridge"
LAST_FILE="$STATE_DIR/last-renewal"        # 上次成功的时间（Unix 秒）
LOG_FILE="$STATE_DIR/renew-last.log"       # 最近一次运行的完整输出
HISTORY_FILE="$STATE_DIR/renew-history.log" # 每次运行一行结果
BACKUP_DIR="$STATE_DIR/profile-backup"     # 最近一次挪走的旧描述文件
LOCK_DIR="$STATE_DIR/renew.lock"
PROFILES_DIR="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
DUE_SECONDS=$((5 * 24 * 3600))
FRESH_SECONDS=$((6 * 24 * 3600))           # 新描述文件至少还剩 6 天才算续上了
PROFILE_NAMES=(
  "iOS Team Provisioning Profile: com.charleschen.ClipBridge"
  "iOS Team Provisioning Profile: com.charleschen.ClipBridge.ClipBridgeKeyboard"
  "iOS Team Provisioning Profile: com.charleschen.ClipBridge.ClipBridgeShare"
)
PY=/usr/bin/python3

mkdir -p "$STATE_DIR" "$BACKUP_DIR"

stamp() { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "$(stamp) $*" | tee -a "$LOG_FILE"; }
notify() { /usr/bin/osascript -e "display notification \"$2\" with title \"$1\"" >/dev/null 2>&1 || true; }
fail() {
  log "失败：$1"
  echo "$(stamp) 失败：$1" >> "$HISTORY_FILE"
  notify "ClipBridge 续签失败" "$1"
  exit 1
}

# --if-due：没到 5 天就安静退出，不动日志
if [[ "${1:-}" == "--if-due" && -f "$LAST_FILE" ]]; then
  last=$(cat "$LAST_FILE" 2>/dev/null || echo 0)
  if (( $(date +%s) - last < DUE_SECONDS )); then
    exit 0
  fi
fi

# 同一时间只跑一个（登录时和定时可能撞在一起）；超过 2 小时的锁当作上次被强行中断留下的
if [[ -d "$LOCK_DIR" ]] && (( $(date +%s) - $(stat -f %m "$LOCK_DIR") > 7200 )); then
  rmdir "$LOCK_DIR" 2>/dev/null
fi
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "$(stamp) 已有一个续签在跑，跳过" >> "$HISTORY_FILE"
  exit 0
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null' EXIT

: > "$LOG_FILE"
log "开始续签（${1:-立即}）"

xcodebuild -version >> "$LOG_FILE" 2>&1 || fail "找不到 Xcode"

# 找连着的 iPhone：可用 CLIPBRIDGE_UDID 指定，否则取第一台已连接的真机
UDID="${CLIPBRIDGE_UDID:-}"
if [[ -z "$UDID" ]]; then
  DEVICES_JSON="$STATE_DIR/devices.json"
  xcrun devicectl list devices --json-output "$DEVICES_JSON" >> "$LOG_FILE" 2>&1
  UDID=$("$PY" -I - "$DEVICES_JSON" <<'EOF'
import json, sys
try:
    devices = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    devices = []
for d in devices:
    hp = d.get("hardwareProperties", {})
    cp = d.get("connectionProperties", {})
    if hp.get("reality") == "physical" and hp.get("platform") == "iOS" and cp.get("tunnelState") == "connected":
        print(hp.get("udid", ""))
        break
EOF
)
  rm -f "$DEVICES_JSON"
fi
[[ -n "$UDID" ]] || fail "该续签了：用数据线把 iPhone 连上 Mac 并解锁，再运行 scripts/renew-ios.sh（定时任务明天也会再试）"
log "设备 $UDID"

profile_name() { security cms -D -i "$1" 2>/dev/null | plutil -extract Name raw -o - - 2>/dev/null; }
is_ours() {
  local p
  for p in "${PROFILE_NAMES[@]}"; do [[ "$1" == "$p" ]] && return 0; done
  return 1
}
have_profile() {
  local f
  for f in "$PROFILES_DIR"/*.mobileprovision; do
    [[ -e "$f" && "$(profile_name "$f")" == "$1" ]] && return 0
  done
  return 1
}
restore_profiles() {
  local f
  for f in "$BACKUP_DIR"/*.mobileprovision; do
    [[ -e "$f" ]] || continue
    have_profile "$(profile_name "$f")" || mv "$f" "$PROFILES_DIR"/
  done
  log "已把旧描述文件放回"
}

# 挪走旧描述文件（备份目录只留这一次的）
rm -f "$BACKUP_DIR"/*.mobileprovision
moved=0
for f in "$PROFILES_DIR"/*.mobileprovision; do
  [[ -e "$f" ]] || continue
  if is_ours "$(profile_name "$f")"; then
    mv "$f" "$BACKUP_DIR"/ && moved=$((moved + 1))
  fi
done
log "挪走旧描述文件 $moved 个"

PROJECT="$REPO/ios/ClipBridge.xcodeproj"
log "编译并签名"
if ! xcodebuild -project "$PROJECT" -scheme ClipBridge -configuration Debug \
     -destination "id=$UDID" -allowProvisioningUpdates build >> "$LOG_FILE" 2>&1; then
  restore_profiles
  fail "编译或签名失败（Xcode 里的 Apple ID 是否还登录着？），详情见 $LOG_FILE"
fi

PRODUCTS_DIR=$(xcodebuild -project "$PROJECT" -scheme ClipBridge -configuration Debug \
  -destination "id=$UDID" -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR = /{print $2; exit}')
APP="$PRODUCTS_DIR/ClipBridge.app"
[[ -d "$APP" ]] || fail "找不到编译产物 $APP"

# 三个 bundle 的描述文件都必须是新的
now=$(date +%s)
expiry=""
for b in "$APP" "$APP"/PlugIns/*.appex; do
  exp=$(security cms -D -i "$b/embedded.mobileprovision" 2>/dev/null | plutil -extract ExpirationDate raw -o - - 2>/dev/null)
  exp_s=$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$exp" +%s 2>/dev/null || echo 0)
  log "$(basename "$b") 描述文件到期 $exp"
  (( exp_s - now > FRESH_SECONDS )) || fail "没拿到新的描述文件（$(basename "$b") 到期 $exp），详情见 $LOG_FILE"
  if [[ -z "$expiry" ]] || (( exp_s < expiry )); then expiry=$exp_s; fi
done
expiry_local=$(date -r "$expiry" '+%m-%d %H:%M')

log "安装到 iPhone"
xcrun devicectl device install app --device "$UDID" "$APP" >> "$LOG_FILE" 2>&1 \
  || fail "签名已续上，但安装失败（手机可能锁着或断开了）：解锁后运行 scripts/renew-ios.sh"

date +%s > "$LAST_FILE"
echo "$(stamp) 成功，新到期 $expiry_local（本地时间）" >> "$HISTORY_FILE"
log "完成，新到期 $expiry_local（本地时间）"
notify "ClipBridge 已续签" "新到期：$expiry_local"
