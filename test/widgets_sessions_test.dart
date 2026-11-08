// Екрани: поле «Команда при відкритті терміналу» з готовими варіантами
// і розділ довідки про постійні сесії.
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vps_admin/app_state.dart';
import 'package:vps_admin/license.dart';
import 'package:vps_admin/models.dart';
import 'package:vps_admin/screens/help_screen.dart';
import 'package:vps_admin/services/ssh_service.dart';
import 'package:vps_admin/services/store.dart';
import 'package:vps_admin/screens/server_edit_screen.dart';
import 'package:vps_admin/terminal_keys.dart';

Widget _app(Widget home, {Locale locale = const Locale('uk')}) => MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );

void main() {
  testWidgets('новий сервер: команда порожня; «tmux» і «screen» підставляють, «Без команди» стирає',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(const ServerEditScreen()));
    await tester.pumpAndSettle();

    final l = lookupAppLocalizations(const Locale('uk'));
    final field = find.widgetWithText(TextFormField, l.fieldStartupCmd);
    expect(field, findsOneWidget);
    String value() => tester.widget<TextFormField>(field).controller!.text;
    expect(value(), '');

    await tester.tap(find.widgetWithText(ActionChip, 'tmux'));
    await tester.pump();
    expect(value(), tmuxStartupCommand());

    await tester.tap(find.widgetWithText(ActionChip, 'screen'));
    await tester.pump();
    expect(value(), screenStartupCommand());

    await tester.tap(find.widgetWithText(ActionChip, l.startupNone));
    await tester.pump();
    expect(value(), '');
  });

  for (final locale in const [Locale('uk'), Locale('en')]) {
    testWidgets('довідка: є розділ «Постійні сесії» ($locale), розгорнуто лише SSH-ключі',
        (tester) async {
      // Довідка — лінивий список, а розгорнутий розділ SSH довгий: високий
      // екран, щоб збудувались усі розділи.
      await tester.binding.setSurfaceSize(const Size(1000, 10000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_app(const HelpScreen(), locale: locale));
      await tester.pumpAndSettle();
      final l = lookupAppLocalizations(locale);
      expect(find.text(l.helpSessionsTitle), findsOneWidget);
      final open = tester
          .widgetList<ExpansionTile>(find.byType(ExpansionTile))
          .where((t) => t.initiallyExpanded)
          .map((t) => (t.title as Text).data)
          .toList();
      expect(open, [l.helpSshTitle]);
    });
  }

  // 08.11.2026: форма показувала приватний ключ відкритим текстом, і він
  // потрапив на знімок екрана, надісланий у чат.
  testWidgets('збережений ключ прихований; «Замінити» без нового ключа його не стирає',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const fake = '-----BEGIN OPENSSH PRIVATE KEY-----\nFAKEKEYBODY42\n-----END OPENSSH PRIVATE KEY-----';
    final server = ServerProfile(name: 'srv', host: 'vps.example.com', username: 'u');
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final store = await Store.open();
    await store.saveSecret(server.id, const ServerSecret(privateKeyPem: fake));
    final app = AppState(store, SshService(), FreeLicenseService());
    await app.init();
    await app.upsertServer(server);

    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: app,
      child: _app(Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ServerEditScreen(existing: server))),
          child: const Text('open'),
        ),
      )),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final l = lookupAppLocalizations(const Locale('uk'));

    expect(find.textContaining('FAKEKEYBODY42'), findsNothing, reason: 'ключ видно на екрані');
    expect(find.text(l.keyStoredTitle), findsOneWidget);

    await tester.tap(find.text(l.keyShow));
    await tester.pumpAndSettle();
    expect(find.textContaining('FAKEKEYBODY42'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l.keyReplace));
    await tester.pumpAndSettle();
    expect(find.textContaining('FAKEKEYBODY42'), findsNothing);
    await tester.tap(find.byTooltip(l.save));
    await tester.pumpAndSettle();
    expect((await store.loadSecret(server.id))?.privateKeyPem, fake);
  });

  // 08.11.2026: на свіжій установці (порожній список-константа) перший сервер
  // не зберігався — upsertServer падав на add у незмінний список.
  test('свіжа установка: перший сервер додається', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final app = AppState(await Store.open(), SshService(), FreeLicenseService());
    await app.init();
    expect(app.servers, isEmpty);
    await app.upsertServer(ServerProfile(name: 'a', host: 'h', username: 'u'),
        secret: const ServerSecret(password: 'p'));
    expect(app.servers.map((s) => s.name), ['a']);
  });
}
