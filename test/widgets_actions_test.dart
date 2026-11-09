// Швидкі дії: результат видно одразу після натискання.
//
// 09.11.2026 на планшеті: результат додавався в самий кінець списку, під
// усі дії, і на екрані після натискання не змінювалось нічого — дія
// виглядала зламаною, хоча відпрацювала.
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vps_admin/app_state.dart';
import 'package:vps_admin/license.dart';
import 'package:vps_admin/models.dart';
import 'package:vps_admin/screens/quick_actions_tab.dart';
import 'package:vps_admin/services/ssh_service.dart';
import 'package:vps_admin/services/store.dart';
import 'package:vps_admin/theme.dart';

/// SSH без мережі: «підключено» до заданого сервера, exec повертає готове.
class _FakeSsh extends SshService {
  _FakeSsh(this.serverId);
  final String serverId;
  final commands = <String>[];

  @override
  bool get isConnected => true;

  @override
  String? get connectedServerId => serverId;

  @override
  Future<CommandResult> exec(String command) async {
    commands.add(command);
    return CommandResult('tmux 9.9-test\n', '', 0);
  }
}

void main() {
  testWidgets('результат дії видно на екрані одразу, без прогортання; «×» його ховає',
      (tester) async {
    // Телефон: список дій значно довший за екран.
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final server = ServerProfile(name: 'srv', host: 'vps.example.com', username: 'u');
    final ssh = _FakeSsh(server.id);
    final app = AppState(await Store.open(), ssh, FreeLicenseService());
    await app.init();
    await app.upsertServer(server, secret: const ServerSecret(password: 'p'));
    await app.setActive(server.id);

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: app),
        ChangeNotifierProvider<SshService>.value(value: ssh),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        locale: const Locale('uk'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const QuickActionsTab(),
      ),
    ));
    await tester.pumpAndSettle();
    final l = lookupAppLocalizations(const Locale('uk'));

    final action = find.text(l.qaTmuxCheck);
    // Вертикальний список дій (у полі пошуку свій, горизонтальний Scrollable).
    final list = find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down);
    await tester.scrollUntilVisible(action, 200, scrollable: list.first);
    await tester.tap(action);
    await tester.pumpAndSettle();

    expect(ssh.commands, hasLength(1));
    expect(find.text('tmux 9.9-test').hitTestable(), findsOneWidget,
        reason: 'результат не видно на екрані після натискання');
    expect(find.textContaining(l.qaTmuxCheck).hitTestable(), findsWidgets);

    await tester.tap(find.byTooltip(l.closeResult));
    await tester.pumpAndSettle();
    expect(find.text('tmux 9.9-test'), findsNothing);
  });
}
