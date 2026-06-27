# VPS Admin — pocket VS Code over SSH

Manage your VPS servers from your Android phone: terminal, files, server info and an
AI assistant — in one app. Your SSH keys never leave your device.

> **Open-core.** This repository is the free core. Pro features (license activation,
> unlimited servers, alerts) live in a private module and ship in the official build.

## Features

| Tab | What it does |
|-----|--------------|
| **Servers** | Add / edit / delete VPS profiles, pick the active one, connect. Free: 1 server. |
| **Info** | Live dashboard: hostname/kernel, uptime, `free -h`, `df -h`, top processes, `docker ps`. |
| **Terminal** | Full interactive SSH shell (`dartssh2` + `xterm`) with helper keys. |
| **Files** | SFTP browser; open a text file in the editor and save it back. |
| **AI** | Chat with Claude; commands in ```` ```bash ```` blocks run over SSH on confirmation. |
| **Actions** | One-tap buttons for common commands. |

Light/dark theme (follows system), English + Ukrainian.

## Tech

Flutter · [`dartssh2`](https://pub.dev/packages/dartssh2) (SSH shell + SFTP) ·
[`xterm`](https://pub.dev/packages/xterm) · [`flutter_secure_storage`](https://pub.dev/packages/flutter_secure_storage)
(keys in Android Keystore) · [`provider`](https://pub.dev/packages/provider).

## Security

- SSH passwords / private keys and the Anthropic API key are stored **only** in the
  Android Keystore via `flutter_secure_storage` — never in git, never in plain prefs.
- Optional biometric / PIN lock on launch.

## Build

```bash
flutter pub get
flutter run            # connected device / emulator
flutter build apk --release
```

Min Android SDK 23.

## Free vs Pro

The free build is limited to **1 server**. Pro (paid license key) unlocks unlimited
servers and upcoming features (threshold alerts, history). Buy & enter the key in
**Settings → License**.

## License

Source-available. Pro module and branding are proprietary. (OSS license for the core — TBD.)
