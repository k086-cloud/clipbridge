# ClipBridge

Clipboard sync between a Windows PC and an iPhone on the same Wi-Fi.

The PC runs a small Python service that watches the Windows clipboard and
exposes it over HTTP. The phone side (an iOS keyboard extension and a share
extension) talks to that service to read the PC clipboard and to push text
back to it.

## Repository layout

```
clipbridge/
  README.md
  .gitignore
  windows-server/    Python service for the PC side (done, text only)
  ios/               iOS keyboard + share extensions (planned, built on a Mac)
```

## Status

| Part | State |
|---|---|
| Windows server (`windows-server/`) | v0.1: plain text, clipboard polling, HTTP API with bearer token, QR pairing |
| iOS keyboard extension | not started |
| iOS share extension | not started |

## Quick start (Windows)

See [windows-server/README.md](windows-server/README.md) for installation,
running the service, testing the API with a browser or `curl`, and the
firewall rule you may need.

## How pairing will work

On every start the Windows service prints its LAN address, port and pairing
token, plus a QR code encoding `clipbridge://pair?host=...&port=...&token=...`.
The iOS app will scan that code once and store the values.
