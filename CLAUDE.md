# VPS Admin — гайд для Claude / розробника

Це **публічне open-core ядро** Android-додатка «VPS Admin» (кишеньковий VS Code по SSH).
Цей файл — щоб будь-яка нова сесія Claude Code, відкрита в цій теці, одразу мала контекст.

## Що це
Flutter Android-застосунок для керування VPS із телефона: **Сервери, Інфо (метрики),
Термінал (SSH shell), Файли (SFTP+редактор), AI-чат, Швидкі дії**. Ключі — лише в Android
Keystore (`flutter_secure_storage`). Теми світла/темна, мови EN/UK.

## Архітектура (lib/)
- `main.dart` — старт, провайдери (AppState, SshService, LicenseService), MaterialApp (тема/локаль).
- `app_state.dart` — центральний стан (сервери, активний, тема, мова, AI-провайдер, custom-дії).
- `models.dart` — ServerProfile, ServerSecret, QuickAction (id/group), ChatMessage.
- `license.dart` — інтерфейс ліцензії; `FreeLicenseService` (open-core: безкоштовно, без ліміту;
  `kMonetizationEnabled=false`). Pro-модуль приватний, у цей репо НЕ входить.
- `services/` — `ssh_service.dart` (dartssh2: shell/exec/SFTP), `ai_service.dart`
  (Claude/OpenAI/Gemini/OpenAI-сумісний), `store.dart` (prefs + secure storage).
- `screens/` — по вкладці; `widgets.dart` — спільне (RequireConnection, MonoOutput, GroupHeader, SaveBar).
- `seed_data.dart` — стартові сервери (порожньо) + поширені «Швидкі дії».
- `l10n/` — ARB (en/uk); генерується `flutter gen-l10n` (конфіг `l10n.yaml`).

## Збірка / запуск
```bash
flutter pub get
flutter gen-l10n
flutter analyze
flutter run                 # пристрій/емулятор
flutter build apk --release # build/app/outputs/flutter-apk/app-release.apk
```
Min Android SDK 23.

## Реліз
APK у **GitHub Releases** (не в git; `*.apk` у .gitignore). Тег `vX.Y.Z`:
```bash
gh release create vX.Y.Z --title "..." --notes "..." vps-admin-X.Y.Z.apk
```

## Гочі
- Проєкт у **OneDrive** → інколи лочить `build/`: `rm -rf build/app/intermediates` і повторити.
- `flutter gen-l10n` міг падати через ACL на `lib/l10n` — перестворити теку.
- Іконки: `assets/icon/*` + `dart run flutter_launcher_icons`.

## Open-core
Цей публічний репо = **free-ядро**. Офіційний білд (із приватним Pro-модулем, реальними
передзаповненими серверами розробника та dev-секретами) живе в окремому **приватному** репо;
сюди потрапляє лише санітизована вільна частина. НЕ додавати сюди реальні IP/ключі/секрети.
