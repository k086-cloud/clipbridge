# ClipBridge

Clipboard sync between a Windows PC and an iPhone on the same Wi-Fi, plain
text only. v0.1 is complete and verified on a real iPhone (2026-11-03).

- **PC → phone**: a custom iOS keyboard shows the last 5 things copied on the
  PC; tap a card to insert it into whatever you are typing.
- **Phone → PC**: select text in any app → Share → ClipBridge, and it lands on
  the PC clipboard.
- The PC runs a small Python service (FastAPI) that watches the Windows
  clipboard and exposes it over HTTP with a bearer token. The phone pairs by
  scanning a QR code the service prints.

## Repository layout

```
clipbridge/
  README.md               this file: setup from zero
  CLAUDE.md               project context for Claude Code (decisions, contracts, pitfalls)
  windows-server/         Python service for the PC (v0.3.0)
  ios/
    ClipBridge.xcodeproj  Xcode 27 project (JSON project format, needs Xcode 27+)
    ClipBridge/           main app: pairing, connection test, setup guide (SwiftUI)
    ClipBridgeKeyboard/   custom keyboard extension (UIKit)
    ClipBridgeShare/      share extension (UIKit)
    ClipBridgeKit/        shared Swift package: HTTP client, pairing store, tests
```

## Status

| Part | State |
|---|---|
| Windows server (`windows-server/`) | v0.3.0: clipboard polling, HTTP API with bearer token, QR pairing, limits reported in `/health`, clearing the history |
| iOS main app | done: QR / manual pairing, connection test with hints, keyboard setup guide, clearing the PC history (needs server 0.3.0+) |
| iOS keyboard extension | done: last 5 PC items as cards, insert on tap, refresh, send the phone clipboard, space/backspace |
| iOS share extension | done: text only, posts to the PC, shows the result or the reason it failed |

Not in v0.1: images and files, history persistence on the PC, HTTPS, mDNS
discovery, auto-start on Windows, a tray icon.

## Setup from zero

You need a Windows PC and a Mac with Xcode 27 on the same Wi-Fi as the
iPhone, and an Apple ID signed in to Xcode (a free "Personal Team" is enough;
see the limits below).

### 1. Start the service on Windows

Follow [windows-server/README.md](windows-server/README.md): create the venv,
`pip install -r requirements.txt`, run `python -m clipbridge_server`, allow
Python through the firewall on **private** networks. The banner prints the
LAN address, port, token and a QR code. Keep that window open.

Check from the phone: open `http://<LAN address>:8765/health` in Safari. A
JSON reply means the phone can reach the PC.

### 2. Build and install the iOS app from the Mac

1. Clone the repository and open `ios/ClipBridge.xcodeproj` in Xcode 27.2 or
   newer (the project file is the JSON `.xcproj` format; older Xcode cannot
   open it).
2. Select the project → each of the three targets (`ClipBridge`,
   `ClipBridgeKeyboard`, `ClipBridgeShare`) → *Signing & Capabilities* → pick
   your team. With a Personal Team you must also change the three bundle IDs
   to ones you own, keeping the extension IDs prefixed by the app ID, and
   change the App Group (`group.<your app id>`) and keychain group in
   `ios/ClipBridgeKit/Sources/ClipBridgeKit/ClipBridgeIdentifiers.swift` to
   match what you enter in Xcode. (This repository is set up for the
   maintainer's team `L24ST657GM` and bundle ID `com.charleschen.ClipBridge`.)
3. Connect the iPhone with a cable, enable *Developer Mode* on the phone
   (Settings → Privacy & Security → Developer Mode, restart), select the phone
   as the run destination and press ⌘R. On first install, trust the developer
   on the phone: Settings → General → VPN & Device Management → your Apple ID
   → Trust, then ⌘R again.

### 3. Pair the phone

1. Open ClipBridge on the phone → *扫描电脑上的二维码* → allow the camera →
   point it at the QR code in the PC terminal → *保存*. (The iOS Camera app
   also recognises the code and offers *Open in ClipBridge*; manual entry of
   host/port/token is available as a fallback.)
2. Tap *测试连接*. If iOS asks whether ClipBridge may find devices on the
   local network, allow it. Both rows turn green when the PC is reachable and
   the token is right; otherwise the hint under the result says what to fix.

### 4. Enable the keyboard

1. Settings → General → Keyboard → Keyboards → Add New Keyboard → under
   *Third-Party Keyboards* tap **ClipBridge** and turn on
   **ClipBridgeKeyboard**.
2. Back in the Keyboards list tap *ClipBridge — ClipBridgeKeyboard* and turn
   on **Allow Full Access** (the keyboard cannot reach the network without it;
   it only talks to your own PC).
3. In any text field, long-press the globe key and pick ClipBridge. The
   keyboard lists the last 5 texts copied on the PC; tap one to insert it.
   *刷新* fetches again, *发送剪贴板* sends the phone clipboard to the PC
   (iOS asks once per copied text whether the keyboard may paste).

### 5. Send text from the phone

Select text in Safari, Notes or any app → Share → **ClipBridge**. The sheet
shows *已发送到电脑* and closes; press Ctrl+V on the PC. ClipBridge only
appears when the shared item is text. The first time, it may be hidden under
*More* in the share sheet's app row.

### 6. Clear the history on the PC

The PC keeps the last texts in memory (20 by default; the keyboard shows
the newest 5 as cards). To wipe them, open the ClipBridge app → *清空电脑上的历史* → confirm.
The PC clipboard itself is not touched, and the keyboard stays empty until
something new is copied on the PC. This needs server 0.3.0 or newer; with an
older one the app says to update it (`git pull` on the PC and restart the
service).

## Free Apple ID (Personal Team) limits

- Provisioning profiles expire after **7 days**: the app, keyboard and share
  extension stop opening together. Connect the phone and press ⌘R in Xcode
  again; the keyboard stays enabled and keeps Full Access.
- At most 10 App IDs per 7 days (this project uses 3, so do not rename the
  bundle IDs casually), 3 devices, and 3 apps installed per device (the
  extensions may count, so keep no other free-signed apps on the phone).
- No App Groups/Keychain Sharing restriction: both capabilities work on a
  Personal Team with Xcode 27.2 (verified). Push notifications, iCloud and
  Universal Links do not, and are not needed.
- Xcode 27 can only install on iOS 17 or newer; the deployment target is
  iOS 17.6.

## Security

The token and every clipboard text travel as plain HTTP on the LAN. Use
ClipBridge only on a home Wi-Fi network or the phone's own hotspot, never on
shared or public Wi-Fi. To rotate the token, delete
`windows-server/config.json`, restart the service and pair again.

## Development

- Windows side: see [windows-server/README.md](windows-server/README.md)
  (`pytest` for the tests; they also run on the Mac).
- iOS shared package: `cd ios/ClipBridgeKit && swift test` runs the unit
  tests on the Mac without a simulator (network is mocked, Keychain uses an
  in-memory store).
- Build everything for a device from the command line:
  `xcodebuild -project ios/ClipBridge.xcodeproj -scheme ClipBridge -sdk iphoneos -destination 'generic/platform=iOS' -allowProvisioningUpdates build`.
- The API contract, storage design and known pitfalls are kept in
  [CLAUDE.md](CLAUDE.md).
