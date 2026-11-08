// Постійні сесії (tmux/screen), команда при відкритті терміналу, клавіша Ctrl
// і «публічне ядро без особистого»: юніт-тести без плагінів і без мережі.
import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vps_admin/models.dart';
import 'package:vps_admin/seed_data.dart';
import 'package:vps_admin/shell_link.dart';
import 'package:vps_admin/terminal_keys.dart';

void main() {
  group('ServerProfile.startupCommand', () {
    test('зберігається й читається', () {
      final p = ServerProfile(
        name: 'T',
        host: 'vps.example.com',
        username: 'ubuntu',
        startupCommand: 'tmux new -A -s work',
      );
      final back = ServerProfile.fromJson(p.toJson());
      expect(back.startupCommand, 'tmux new -A -s work');
      expect(p.copy().startupCommand, 'tmux new -A -s work');
    });

    test('профіль зі старої версії (без поля) читається з порожньою командою', () {
      final old = {
        'id': 'x',
        'name': 'Old',
        'host': 'h',
        'port': 22,
        'username': 'u',
        'auth': 'key',
        'defaultDir': '/srv',
        'group': '',
      };
      expect(ServerProfile.fromJson(old).startupCommand, '');
    });

    test('за замовчуванням команди немає — новий сервер нічого сам не запускає', () {
      expect(ServerProfile(name: 'n', host: 'h', username: 'u').startupCommand, '');
    });
  });

  group('shellStartupInput', () {
    test('тека, потім команда — кожна з Enter', () {
      expect(
        shellStartupInput(dir: '/home/me', command: 'tmux new -A -s main'),
        'cd "/home/me"\ntmux new -A -s main\n',
      );
    });

    test('без команди — лише перехід у теку (як було)', () {
      expect(shellStartupInput(dir: '/srv', command: ''), 'cd "/srv"\n');
      expect(shellStartupInput(dir: '/srv', command: '   '), 'cd "/srv"\n');
    });

    test('корінь і порожня тека не дають cd', () {
      expect(shellStartupInput(dir: '/', command: 'htop'), 'htop\n');
      expect(shellStartupInput(dir: null, command: null), '');
    });
  });

  group('готові команди сесій', () {
    test('tmux підключає або створює сесію з назвою', () {
      expect(tmuxStartupCommand(), 'tmux new -A -s main');
      expect(tmuxStartupCommand('work'), 'tmux new -A -s work');
    });

    test('screen перепідключає або створює', () {
      expect(screenStartupCommand('work'), 'screen -D -R -S work');
    });

    test('меню tmux: префікс Ctrl+b (0x02) і клавіша', () {
      expect(TmuxKey.detach.sequence, '\x02d');
      expect(TmuxKey.newWindow.sequence, '\x02c');
      expect(TmuxKey.nextWindow.sequence, '\x02n');
      expect(TmuxKey.chooseSession.sequence, '\x02s');
      expect(TmuxKey.scrollMode.sequence, '\x02[');
      expect(screenDetachSequence, '\x01d');
    });
  });

  group('ctrlChar — екранна клавіша Ctrl', () {
    test('літери', () {
      expect(ctrlChar('a'), '\x01');
      expect(ctrlChar('b'), '\x02');
      expect(ctrlChar('c'), '\x03');
      expect(ctrlChar('C'), '\x03', reason: 'Shift не має значення');
      expect(ctrlChar('z'), '\x1a');
    });

    test('символи [ \\ ] ^ _, пробіл, @ і ?', () {
      expect(ctrlChar('['), '\x1b');
      expect(ctrlChar('\\'), '\x1c');
      expect(ctrlChar(']'), '\x1d');
      expect(ctrlChar('_'), '\x1f');
      expect(ctrlChar(' '), '\x00');
      expect(ctrlChar('@'), '\x00');
      expect(ctrlChar('?'), '\x7f');
    });

    test('без керуючого відповідника — null (символ іде як є)', () {
      expect(ctrlChar('1'), isNull);
      expect(ctrlChar('й'), isNull);
      expect(ctrlChar('ab'), isNull);
      expect(ctrlChar(''), isNull);
    });
  });

  // 08.11.2026 на планшеті: exit у Терміналі → клавіатура сховалась → розмір
  // вікна пішов у закритий канал → OpenSSH розірвав УСЕ з'єднання
  // («server_input_channel_req: unknown channel»).
  group('ShellLink — після закриття каналу в нього нічого не йде', () {
    late List<String> calls;
    late Completer<void> done;
    late ShellLink link;
    setUp(() {
      calls = [];
      done = Completer<void>();
      link = ShellLink(
        write: (d) => calls.add('write ${String.fromCharCodes(d)}'),
        resize: (w, h) => calls.add('resize $w x $h'),
        close: () => calls.add('close'),
        done: done.future,
      );
    });

    test('поки канал відкритий — усе проходить', () {
      link.send('ls\n');
      link.resize(100, 30);
      expect(calls, ['write ls\n', 'resize 100 x 30']);
    });

    test('сервер закрив канал — ні введення, ні розміру, ні повторного close', () async {
      done.complete();
      await Future<void>.delayed(Duration.zero);
      link.send('x');
      link.resize(100, 30);
      link.close();
      expect(link.isOpen, isFalse);
      expect(calls, isEmpty);
    });

    test('завершення з помилкою теж закриває', () async {
      done.completeError(StateError('transport'));
      await Future<void>.delayed(Duration.zero);
      link.resize(1, 1);
      expect(calls, isEmpty);
    });

    test('у застосунку розмір shell міняє лише ShellLink', () {
      final offenders = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('shell_link.dart'))
          .where((f) => f.readAsStringSync().contains('resizeTerminal('))
          .map((f) => f.path)
          .toList();
      expect(offenders, isEmpty, reason: 'напряму в канал — ризик розриву з\'єднання');
    });

    test('наше закриття — один раз, далі тиша', () {
      link.close();
      link.close();
      link.send('x');
      expect(calls, ['close']);
    });
  });

  group('вбудовані швидкі дії', () {
    for (final locale in const [Locale('en'), Locale('uk')]) {
      test('група «Постійні сесії» є ($locale)', () {
        final l = lookupAppLocalizations(locale);
        final sessions =
            commonQuickActions(l).where((a) => a.group == l.grpSessions).toList();
        expect(sessions.map((a) => a.title),
            containsAll([l.qaTmuxCheck, l.qaTmuxInstall, l.qaTmuxMouse, l.qaTmuxList]));
        final install = sessions.firstWhere((a) => a.title == l.qaTmuxInstall);
        expect(install.dangerous, isTrue, reason: 'встановлення — з підтвердженням');
      });

      test('повідомлення, вбудовані в команди, не ламають лапки shell ($locale)', () {
        final l = lookupAppLocalizations(locale);
        for (final m in [l.msgTmuxMissing, l.msgTmuxNoSessions, l.msgCronEmpty]) {
          expect(m, isNot(matches(r'["$`\\!]')), reason: m);
        }
      });
    }

    final sh = _findSh();
    test('кожна вбудована команда — синтаксично правильний sh', () async {
      for (final locale in const [Locale('en'), Locale('uk')]) {
        final l = lookupAppLocalizations(locale);
        for (final a in commonQuickActions(l)) {
          final r = await Process.run(sh!, ['-n', '-c', a.command]);
          expect(r.exitCode, 0, reason: '${a.title}: ${a.command}\n${r.stderr}');
        }
      }
    }, skip: sh == null ? 'sh недоступний на цій машині' : false);
  });

  // Публічне ядро йде у Google Play і на GitHub: жодних адрес, назв проєктів
  // чи скриптів конкретного розробника. Його налаштування (сервери, назви
  // сесій, власні дії) живуть лише в застосунку на телефоні.
  test('у публічному коді й перекладах немає особистих налаштувань', () {
    final ip = RegExp(r'\b(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})\b');
    // Дозволені: документаційні діапазони (RFC 5737) і службові адреси.
    bool allowedIp(Match m) {
      final a = '${m[1]}.${m[2]}.${m[3]}';
      return a == '192.0.2' ||
          a == '198.51.100' ||
          a == '203.0.113' ||
          m[0] == '127.0.0.1' ||
          m[0] == '0.0.0.0';
    }

    final problems = <String>[];
    final libFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') || f.path.endsWith('.arb'));
    for (final f in libFiles) {
      for (final m in ip.allMatches(f.readAsStringSync())) {
        if (!allowedIp(m)) problems.add('${f.path}: IP ${m[0]}');
      }
    }

    // Самі маркери (IP, імена, назви скриптів розробника) теж особисті, тож
    // лежать поза git — у private_markers.local.txt на машині розробника.
    // Перевіряються всі файли, які йдуть у публічний репозиторій.
    final markers = privateMarkers();
    for (final f in trackedTextFiles()) {
      final text = f.readAsStringSync().toLowerCase();
      for (final w in markers) {
        if (text.contains(w)) problems.add('${f.path}: особистий маркер №${markers.indexOf(w) + 1}');
      }
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}

/// Маркери з private_markers.local.txt (поза git). Немає файлу — порожньо.
List<String> privateMarkers() {
  final f = File('private_markers.local.txt');
  if (!f.existsSync()) return const [];
  return f
      .readAsLinesSync()
      .map((l) => l.trim().toLowerCase())
      .where((l) => l.isNotEmpty && !l.startsWith('#'))
      .toList();
}

/// Текстові файли, які git відправить у публічний репозиторій.
List<File> trackedTextFiles() {
  try {
    final r = Process.runSync('git', ['ls-files']);
    if (r.exitCode != 0) throw StateError('git');
    const binary = ['.png', '.jpg', '.jpeg', '.webp', '.ico', '.jar', '.apk', '.keystore', '.jks'];
    return (r.stdout as String)
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !binary.any(l.toLowerCase().endsWith))
        .map(File.new)
        .where((f) => f.existsSync())
        .toList();
  } catch (_) {
    return Directory('lib').listSync(recursive: true).whereType<File>().toList();
  }
}

/// sh для перевірки синтаксису: у PATH або з Git for Windows.
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
