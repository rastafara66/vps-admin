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
- `models.dart` — ServerProfile (у т.ч. `startupCommand` — команда при відкритті терміналу),
  ServerSecret, QuickAction (id/group), ChatMessage.
- `terminal_keys.dart` — чиста логіка терміналу: екранна Ctrl (`ctrlChar`), меню tmux (`TmuxKey`),
  готові команди сесій (`tmuxStartupCommand` / `screenStartupCommand`), текст старту shell.
- `safe_terminal.dart` — `SafeTerminal`: xterm 4.0.0 з виправленими командами стирання на краях екрана
  (на `ESC [ 1 K` у колонці 0 xterm падав, і від екрана tmux лишався верх). Звичайний `Terminal(` у `lib/` заборонено.
- `shell_link.dart` — після закриття каналу shell у нього нічого не йде (інакше OpenSSH рве все з'єднання).
- `auto_reconnect.dart` — `AutoReconnect`: обрив не з волі користувача (Android заморожує застосунок у фоні) →
  підключитися знову самим, щойно людина повернеться; після довгої паузи «живе» з'єднання перевіряється
  `SshService.checkAlive`. «Від'єднатися» кнопкою — без автопідключення. Запускається в `main.dart`.
- `license.dart` — інтерфейс ліцензії; `FreeLicenseService` (open-core: безкоштовно, без ліміту;
  `kMonetizationEnabled=false`). Pro-модуль приватний, у цей репо НЕ входить.
- `services/` — `ssh_service.dart` (dartssh2: shell/exec/SFTP; `exec` бере код завершення з мітки, яку друкує
  сама оболонка, — `wrapForExitCode`: dartssh2 губить `exit-status` швидких команд), `ai_service.dart`
  (Claude/OpenAI/Gemini/OpenAI-сумісний), `store.dart` (prefs + secure storage).
- `screens/` — по вкладці; `widgets.dart` — спільне (RequireConnection, MonoOutput, GroupHeader, SaveBar).
- `seed_data.dart` — стартові сервери (порожньо) + поширені «Швидкі дії», зокрема група
  «Постійні сесії (tmux)».
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

## Тести
```bash
flutter test                # модульні й віджет-тести, без мережі
```
- `test/sessions_test.dart` — сесії, Ctrl, швидкі дії (`sh -n` для кожної вбудованої команди) і
  **гейт публічного ядра**: у `lib/` немає IP (крім RFC 5737), а в жодному файлі репо — особистих
  маркерів розробника. Маркери самі особисті, тож лежать поза git: `private_markers.local.txt`
  (рядок — маркер, `#` — коментар; `*.local.txt` у `.gitignore`).
- `test/terminal_render_test.dart` — малювання: перемальовування в стилі tmux доходить до останнього рядка, команди
  стирання/вставки/видалення на краях екрана не кидають виняток і не гублять вивід; гейт «лише `SafeTerminal`».
- `test/exit_code_test.dart` — код завершення через мітку оболонки (справжній `sh`; кожна вбудована дія після
  обгортки — `sh -n`). `test/widgets_actions_test.dart` — результат швидкої дії видно одразу, без прогортання.
- 🔴 Тести логіки й живий тест **не бачать екрана**: зміни терміналу перевіряти ще й на пристрої — зайти в tmux
  з непорожнім екраном, побачити смугу tmux унизу, `adb logcat | grep "E flutter"` — порожньо.
- `test/live_ssh_test.dart` — **ручна** перевірка наживо (мережа + сервер з tmux; 40 команд — 40 кодів завершення), без змінних
  середовища пропускається. Адреса й ключ — лише зі змінних, у репо їх немає:
  `VPS_ADMIN_LIVE_HOST=… VPS_ADMIN_LIVE_KEY=<шлях до ключа> flutter test test/live_ssh_test.dart`
  (тимчасова сесія `vpsadmin_selftest_<pid>`, прибирає її сама; наприкінці навмисно рве своє з'єднання).

## Реліз
APK у **GitHub Releases** (не в git; `*.apk` у .gitignore). Тег `vX.Y.Z`.

🔴 **Збирати з літери диска, а не з `C:\Users\<ім'я>\…`**: Flutter вшиває в `libapp.so` шлях до
згенерованого `dart_plugin_registrant.dart`, тобто ім'я користувача Windows (знайдено 08.11.2026).

```powershell
subst V: "C:\Users\<ім'я>\Projects\VPS admin"     # один раз за сеанс Windows
cd V:\ ; flutter build apk --release
python tool/check_release_apk.py build/app/outputs/flutter-apk/app-release.apk   # 0 = чисто
gh release create vX.Y.Z --title "..." --notes "..." vps-admin-X.Y.Z.apk
```

`check_release_apk.py` шукає в APK ім'я користувача ОС, шляхи `Users/…` і маркери з
`private_markers.local.txt`; код 1 — не публікувати.

## Гочі
- Проєкт у **OneDrive** → інколи лочить `build/`: `rm -rf build/app/intermediates` і повторити.
- `flutter gen-l10n` міг падати через ACL на `lib/l10n` — перестворити теку.
- Іконки: `assets/icon/*` + `dart run flutter_launcher_icons`.

## Open-core
Цей публічний репо = **free-ядро**. Офіційний білд (із приватним Pro-модулем, реальними
передзаповненими серверами розробника та dev-секретами) живе в окремому **приватному** репо;
сюди потрапляє лише санітизована вільна частина. НЕ додавати сюди реальні IP/ключі/секрети.

🔴 **Особисте — лише в налаштуваннях застосунку** (власник, 08.11.2026: застосунок іде в Google
Play). Свої сервери, назви сесій tmux (напр. для Claude Code), власні швидкі дії, cron-рядки
розробник вводить у застосунку на телефоні; у код і переклади — лише загальні можливості з
нейтральними прикладами (`main`, `vps.example.com`, `203.0.113.10`). 08.11 з перекладів прибрано
залишки особистих дій розробника — гейт у `test/sessions_test.dart`.
