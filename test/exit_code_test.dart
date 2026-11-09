// Код завершення одноразових команд (Швидкі дії, Інфо, AI).
//
// 09.11.2026: «tmux: перевірити» на планшеті показала «exit null» і червоний
// значок, хоча вивела «tmux 3.2a». dartssh2 (2.18–2.22) ставить обробник
// запитів каналу лише після відповіді на exec, і швидка команда встигає
// надіслати exit-status раніше — наживо губилось 19 кодів із 40. Тому код
// друкує сама оболонка останнім рядком stdout, а застосунок його вирізає.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vps_admin/seed_data.dart';
import 'package:vps_admin/services/ssh_service.dart';

void main() {
  group('takeExitCode — мітка в кінці stdout', () {
    test('вивід із переведенням рядка — повертається дослівно', () {
      final r = takeExitCode('tmux 3.2a\n\n${exitCodeMark}0\n');
      expect(r.stdout, 'tmux 3.2a\n');
      expect(r.exitCode, 0);
    });

    test('вивід без переведення рядка в кінці — теж дослівно', () {
      final r = takeExitCode('abc\n${exitCodeMark}3\n');
      expect(r.stdout, 'abc');
      expect(r.exitCode, 3);
    });

    test('порожній вивід', () {
      final r = takeExitCode('\n${exitCodeMark}1\n');
      expect(r.stdout, '');
      expect(r.exitCode, 1);
    });

    test('без мітки (оболонку вбито, з\'єднання обірвалось) — код невідомий, вивід як є', () {
      final r = takeExitCode('partial');
      expect(r.stdout, 'partial');
      expect(r.exitCode, isNull);
    });

    test('мітка посеред виводу (сама команда її надрукувала) не чіпається', () {
      const s = 'x\n${exitCodeMark}5\ny';
      expect(takeExitCode(s).stdout, s);
      expect(takeExitCode(s).exitCode, isNull);
    });
  });

  final sh = _findSh();
  group('wrapForExitCode — справжня оболонка', () {
    Future<CommandResult> run(String cmd) async {
      final r = await Process.run(sh!, ['-c', wrapForExitCode(cmd)]);
      final t = takeExitCode(r.stdout as String);
      return CommandResult(t.stdout, r.stderr as String, t.exitCode);
    }

    const cases = <String, (String, int)>{
      'true': ('', 0),
      'false': ('', 1),
      'exit 3': ('', 3),
      'echo hi': ('hi\n', 0),
      'printf no-newline': ('no-newline', 0),
      'echo a; exit 7': ('a\n', 7),
      'echo end # коментар у кінці': ('end\n', 0),
      // Лише вбудовані команди: Git-sh під `flutter test` на Windows не
      // бачить /usr/bin (cat, grep…).
      'read -r x <<EOF\nheredoc\nEOF\necho "\$x"': ('heredoc\n', 0),
      'case x in x) echo case;; esac': ('case\n', 0),
    };
    for (final c in cases.entries) {
      test(c.key.replaceAll('\n', r'\n'), () async {
        final r = await run(c.key);
        expect(r.stdout, c.value.$1, reason: r.stderr);
        expect(r.exitCode, c.value.$2);
      });
    }

    test('кожна вбудована швидка дія лишається синтаксично правильною', () async {
      for (final locale in const [Locale('en'), Locale('uk')]) {
        for (final a in commonQuickActions(lookupAppLocalizations(locale))) {
          final r = await Process.run(sh!, ['-n', '-c', wrapForExitCode(a.command)]);
          expect(r.exitCode, 0, reason: '${a.title}\n${r.stderr}');
        }
      }
    });
  }, skip: sh == null ? 'sh недоступний на цій машині' : false);
}

String? _findSh() {
  for (final c in [
    'sh',
    r'C:\Program Files\Git\usr\bin\sh.exe',
    r'C:\Program Files\Git\bin\sh.exe',
  ]) {
    try {
      if (Process.runSync(c, ['-c', 'true']).exitCode == 0) return c;
    } catch (_) {}
  }
  return null;
}
