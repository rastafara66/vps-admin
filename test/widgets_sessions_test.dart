// Екрани: поле «Команда при відкритті терміналу» з готовими варіантами
// і розділ довідки про постійні сесії.
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vps_admin/screens/help_screen.dart';
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
}
