# ClipBridge Windows server

A small Python service that watches the Windows clipboard and shares it over
HTTP with your phone on the same Wi-Fi. Version 0.2.0 handles plain text
only. The phone side (keyboard + share extension) lives in `../ios`; the
end-to-end setup is in the [root README](../README.md).

What it does:

- polls the clipboard every 300 ms and keeps the last 20 text items in memory
  (id, content, timestamp, source `pc` or `phone`);
- serves a FastAPI app on port 8765 with endpoints to read the latest item,
  read the history, and push text from the phone onto the PC clipboard;
- never records a phone paste a second time as a new PC item;
- generates a random pairing token on first run and requires it as a bearer
  token on every endpoint except `/health`;
- prints the LAN address, port, token and a QR code at startup for pairing;
- ignores or rejects any single text larger than 100 KB.

## Requirements

- Windows 10/11
- Python 3.11 or newer (`py --version`)

## Install

Open PowerShell in this directory (`windows-server`):

```powershell
py -3 -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

For running the tests, install the dev extras instead:

```powershell
pip install -r requirements-dev.txt
```

## Run

```powershell
.\.venv\Scripts\Activate.ps1
python -m clipbridge_server
```

The first start creates `config.json` in this directory with a random token.
The file is listed in `.gitignore`; never commit it. Delete it to get a new
token. Startup prints something like:

```
================================================================
ClipBridge Windows server
================================================================
LAN address : 192.168.1.23
Port        : 8765
Token       : K3f...                                  (43 characters)
Health URL  : http://192.168.1.23:8765/health
Pairing URL : clipbridge://pair?host=192.168.1.23&port=8765&token=K3f...

Scan this with the ClipBridge iOS app to pair:
█▀▀▀▀▀█ ...
================================================================
```

Options: `--port 9000`, `--host 127.0.0.1` (local only), `--no-qr`,
`--log-level DEBUG`, `--config PATH`. Stop the server with `Ctrl+C`.

If the QR code looks garbled, use Windows Terminal, or run with `--no-qr`
and read the pairing URL as text.

## API

All responses are JSON. Every endpoint except `/health` requires the header
`Authorization: Bearer <token>`; without it you get `401`.

| Method | Path | Purpose |
|---|---|---|
| GET | `/health` | Service status, version, history size, uptime, and the limits `max_text_bytes` / `history_size` |
| GET | `/clip/latest` | Newest history item (`404` when there is none yet) |
| GET | `/clip/history?limit=N` | Newest `N` items, newest first (`N` >= 1; anything above `history_size` is clamped to it; default: all) |
| POST | `/clip` | Body `{"content": "text"}`; puts the text on the PC clipboard and records it with source `phone`; returns `201` and the item |

An item looks like:

```json
{
  "id": "0c9d2a4f3b1e4e7f9a5c1d2e3f4a5b6c",
  "content": "hello",
  "timestamp": "2026-11-01T18:04:11.532-04:00",
  "source": "pc"
}
```

Error codes: `401` missing or wrong token, `404` empty history, `413` text
over 100 KB, `422` invalid body or query, `503` the clipboard could not be
written (another program was holding it; retry).

## Try it from this PC

Put the token in a variable first (copy it from the startup banner or from
`config.json`). Replace `192.168.1.23` with the address the banner shows, or
use `127.0.0.1` on the PC itself.

PowerShell:

```powershell
$token = "paste-your-token-here"
$base = "http://127.0.0.1:8765"
$headers = @{ Authorization = "Bearer $token" }

Invoke-RestMethod "$base/health"
Invoke-RestMethod "$base/clip/latest" -Headers $headers
Invoke-RestMethod "$base/clip/history?limit=5" -Headers $headers
Invoke-RestMethod "$base/clip" -Method Post -Headers $headers -ContentType "application/json" -Body '{"content": "hello from curl"}'
```

curl (Windows ships `curl.exe`; in PowerShell type `curl.exe`, not `curl`):

```powershell
curl.exe http://127.0.0.1:8765/health
curl.exe -H "Authorization: Bearer $token" http://127.0.0.1:8765/clip/latest
curl.exe -H "Authorization: Bearer $token" "http://127.0.0.1:8765/clip/history?limit=5"
curl.exe -X POST -H "Authorization: Bearer $token" -H "Content-Type: application/json" -d "{\"content\": \"hello from curl\"}" http://127.0.0.1:8765/clip
```

After the POST, press `Ctrl+V` anywhere: the text is on the clipboard.
Copy some other text and call `/clip/latest` again to see it recorded with
source `pc`.

Browser: `http://127.0.0.1:8765/health` works directly. The other endpoints
need the header, so a plain browser tab shows `401`; the interactive docs at
`http://127.0.0.1:8765/docs` let you click **Authorize**, paste the token,
and call every endpoint.

## Windows Firewall

The server listens on all interfaces (`0.0.0.0`). The first start usually
shows a Windows Defender Firewall prompt for Python; allow it on **private**
networks. If the prompt did not appear or the phone cannot connect, add the
rule yourself from an administrator PowerShell:

```powershell
netsh advfirewall firewall add rule name="ClipBridge 8765" dir=in action=allow protocol=TCP localport=8765
```

Also make sure the Wi-Fi network is set to **Private** in Windows settings;
on Public networks inbound connections are blocked regardless of the rule.

## Use it with the iPhone app

1. Keep this service running; the banner's QR code is the pairing code.
2. Install the iOS app from a Mac with Xcode (see the
   [root README](../README.md), "Setup from zero").
3. On the phone: ClipBridge app → scan the QR code → *测试连接* (both rows
   green) → add the ClipBridge keyboard in Settings and turn on *Allow Full
   Access* → use the keyboard to insert PC clipboard items, and Share →
   ClipBridge to send text to the PC.
4. After `git pull` on the PC, restart the service; the phone picks up the
   new `/health` fields and the clamped `limit` automatically.

If the phone cannot connect: the phone and the PC must be on the same Wi-Fi
subnet (campus networks often isolate clients or route between subnets — a
phone hotspot with the PC joined to it is the reliable fallback), the
firewall rule above must allow inbound TCP 8765, and the token on the phone
must match `config.json` (delete the file to get a new token, then pair
again).

## Test from an iPhone without the app

1. Open Safari and visit `http://<LAN address>:8765/health`. A JSON reply
   proves the phone can reach the PC and the firewall is open.
2. Safari cannot send custom headers, so test the protected endpoints with
   the built-in **Shortcuts** app: create a shortcut with a single
   **Get Contents of URL** action, set the URL to
   `http://<LAN address>:8765/clip/latest`, method GET, and add a header
   `Authorization` = `Bearer <token>`. Run it and the latest PC clipboard
   text appears. For sending text, change the method to POST, request body
   JSON with key `content`, and the text lands on the PC clipboard.
3. Any HTTP client app that supports custom headers works too.

## Run the tests

```powershell
.\.venv\Scripts\Activate.ps1
pytest
```

The tests cover the history buffer, config/token handling, bearer-token
checks, the loop-prevention logic of the clipboard monitor (with a fake
clipboard) and every API endpoint. They never touch the real clipboard.

## Configuration (`config.json`)

| Key | Default | Meaning |
|---|---|---|
| `token` | generated | Bearer token required by the API |
| `host` | `0.0.0.0` | Bind address |
| `port` | `8765` | TCP port |
| `poll_interval_ms` | `300` | How often the clipboard is checked |
| `max_text_bytes` | `102400` | Largest text accepted or recorded (UTF-8 bytes) |
| `history_size` | `20` | Items kept in memory |

## Security notes

- The token is the only protection; anyone on the LAN with it can read and
  write your clipboard. Keep `config.json` private and delete it to rotate.
- Traffic is plain HTTP on your local network. Do not expose the port to the
  internet, and pair/use ClipBridge only on a home Wi-Fi network or the phone's
  own hotspot, never on shared or public Wi-Fi (campus, cafe, hotel): anyone on
  that network can read the token and the clipboard text. If you think the
  token leaked, delete `config.json` and restart (a new token is generated),
  then pair the phone again.
- History lives in memory only and is gone when the server stops.
