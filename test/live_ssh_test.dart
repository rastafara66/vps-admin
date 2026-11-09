// Ручна перевірка наживо: справжнє SSH-з'єднання, постійна сесія tmux,
// від'єднання й повернення, клавіша Ctrl, обрив з'єднання.
//
// Потрібні мережа й сервер з tmux, тому за замовчуванням пропускається.
// Запуск (адреса й ключ — лише зі змінних середовища, у репо їх немає):
//   VPS_ADMIN_LIVE_HOST=host VPS_ADMIN_LIVE_USER=ubuntu \
//   VPS_ADMIN_LIVE_KEY=/path/to/private_key flutter test test/live_ssh_test.dart
//
// Створює на сервері тимчасову сесію tmux `vpsadmin_selftest_<pid>` і прибирає її.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:vps_admin/models.dart';
import 'package:vps_admin/services/ssh_service.dart';
import 'package:vps_admin/shell_link.dart';
import 'package:vps_admin/terminal_keys.dart';

void main() {
  final env = Platform.environment;
  final host = env['VPS_ADMIN_LIVE_HOST'];
  final keyPath = env['VPS_ADMIN_LIVE_KEY'];
  final user = env['VPS_ADMIN_LIVE_USER'] ?? 'ubuntu';
  final skip = (host == null || keyPath == null)
      ? 'ручна перевірка: задайте VPS_ADMIN_LIVE_HOST і VPS_ADMIN_LIVE_KEY'
      : false;

  test('tmux: команда при відкритті, від\'єднання, повернення, Ctrl, обрив', () async {
    final name = 'vpsadmin_selftest_$pid';
    final ssh = SshService();
    final server = ServerProfile(
      name: 'live',
      host: host!,
      username: user,
      defaultDir: '/tmp',
      startupCommand: tmuxStartupCommand(name),
    );
    await ssh.connect(
        server, ServerSecret(privateKeyPem: File(keyPath!).readAsStringSync()));
    expect(ssh.isConnected, isTrue, reason: ssh.error);

    Future<String> sh(String c) async => (await ssh.exec(c)).combined;
    Future<void> until(Future<bool> Function() ok, String what) async {
      for (var i = 0; i < 40; i++) {
        if (await ok()) return;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      fail('не дочекались: $what');
    }

    Future<bool> attached() async =>
        (await sh('tmux list-clients -t $name 2>/dev/null')).trim().isNotEmpty;
    Future<String> pane() => sh('tmux capture-pane -p -t $name 2>/dev/null');

    try {
      await sh('tmux kill-session -t $name 2>/dev/null; true');

      // 1. Термінал відкрився → команда при відкритті створює сесію й підключає.
      var shell = await ssh.startShell(width: 100, height: 30);
      void send(String s) => shell.write(Uint8List.fromList(utf8.encode(s)));
      shell.stdout.listen((_) {});
      send(shellStartupInput(dir: server.defaultDir, command: server.startupCommand));
      await until(attached, 'сесія $name з клієнтом');

      const mark = 'VPSADMIN_MARK_42';
      send('echo $mark\n');
      await until(() async => (await pane()).contains(mark), 'мітка в сесії');

      // 2. Ctrl з панелі: Ctrl, потім c зупиняє команду всередині tmux.
      send('sleep 307\n');
      Future<bool> sleeping() async =>
          (await sh('pgrep -u "\$(id -u)" -f "^sleep 307\$" >/dev/null && echo y || echo n'))
              .trim() ==
          'y';
      await until(sleeping, 'sleep запущено');
      send(ctrlChar('c')!);
      await until(() async => !await sleeping(), 'Ctrl+c зупинив sleep');

      // 3. Меню «tmux» → Від'єднатися: клієнта немає, сесія жива.
      send(TmuxKey.detach.sequence);
      await until(() async => !await attached(), 'від\'єднання');
      expect((await sh('tmux has-session -t $name && echo alive')).trim(), 'alive');
      shell.close();

      // 4. Новий термінал (як «Відкрити знову» чи наступний вхід) — та сама сесія.
      shell = await ssh.startShell(width: 100, height: 30);
      shell.stdout.listen((_) {});
      send(shellStartupInput(dir: server.defaultDir, command: server.startupCommand));
      await until(attached, 'повернення в сесію');
      expect(await pane(), contains(mark), reason: 'це та сама сесія, не нова');
      expect((await sh('tmux ls')).split('\n').where((l) => l.startsWith('$name:')).length, 1);
      shell.close();

      await sh('tmux kill-session -t $name');

      // 5. exit у shell, а через 2 с — зміна розміру (сховалась клавіатура).
      //    Без ShellLink OpenSSH розриває все з'єднання (08.11.2026, планшет).
      final plain = await ssh.startShell(width: 80, height: 24);
      final link = ShellLink.ssh(plain);
      plain.stdout.listen((_) {});
      link.send('exit\n');
      await plain.done.timeout(const Duration(seconds: 10));
      await Future<void>.delayed(const Duration(seconds: 2));
      link.resize(120, 40);
      link.send('x');
      link.close();
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(ssh.isConnected, isTrue, reason: 'з\'єднання пережило закритий shell');
      expect((await sh('echo alive')).trim(), 'alive');

      // 6. Обрив: сервер закриває саме це з'єднання → сервіс це помічає.
      expect(ssh.connectionLost, isFalse);
      unawaited(ssh.exec(r'kill -9 $PPID').catchError((_) => CommandResult('', '', -1)));
      await until(() async => !ssh.isConnected, 'обрив помічено');
      expect(ssh.connectionLost, isTrue);
      expect(ssh.status, SshStatus.disconnected);
    } finally {
      if (ssh.isConnected) {
        await sh('tmux kill-session -t $name 2>/dev/null; true');
      }
      await ssh.disconnect();
    }
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));

  // 09.11.2026 на планшеті: «tmux: перевірити» вивела «tmux 3.2a», але з
  // червоним значком і «exit null» — код завершення іноді не доходив.
  test('швидкі дії: код завершення приходить щоразу', () async {
    final ssh = SshService();
    final server = ServerProfile(name: 'live', host: host!, username: user);
    await ssh.connect(
        server, ServerSecret(privateKeyPem: File(keyPath!).readAsStringSync()));
    expect(ssh.isConnected, isTrue, reason: ssh.error);
    try {
      // Перевірка «живості» після повернення з фону (AutoReconnect).
      expect(await ssh.checkAlive(), isTrue);
      expect(ssh.isConnected, isTrue);
      const cases = {'true': 0, 'false': 1, 'tmux -V >/dev/null': 0, 'exit 3': 3};
      final wrong = <String>[];
      for (var i = 0; i < 10; i++) {
        for (final c in cases.entries) {
          final r = await ssh.exec(c.key);
          if (r.exitCode != c.value) wrong.add('${c.key}: ${r.exitCode}');
        }
      }
      expect(wrong, isEmpty, reason: 'з ${cases.length * 10} команд');
    } finally {
      await ssh.disconnect();
    }
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));
}
