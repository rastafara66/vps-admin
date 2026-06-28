# VPS Admin — pocket VS Code over SSH

Manage your VPS servers from your Android phone: terminal, files, server info and an
AI assistant — in one app. Your SSH keys never leave your device.

> **Free and open.** Unlimited servers, all features, no subscription, no account.

## Features

| Tab | What it does |
|-----|--------------|
| **Servers** | Add / edit / delete VPS profiles, pick the active one, connect. As many as you like. |
| **Info** | Live dashboard: hostname/kernel, uptime, `free -h`, `df -h`, top processes, `docker ps`. |
| **Terminal** | Full interactive SSH shell (`dartssh2` + `xterm`) with helper keys. |
| **Files** | SFTP browser; open a text file in the editor and save it back. |
| **AI** | Chat with an AI assistant — Claude, ChatGPT, Gemini or any OpenAI-compatible endpoint (bring your own key); commands in ```` ```bash ```` blocks run over SSH on confirmation. |
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

## Install

Grab the latest APK from **[Releases](https://github.com/rastafara66/vps-admin/releases/latest)**,
open it on Android and allow install from unknown sources. Min Android 7 (SDK 23).

## Build

```bash
flutter pub get
flutter run            # connected device / emulator
flutter build apk --release
```

## License

Source-available. See the repository for details.
