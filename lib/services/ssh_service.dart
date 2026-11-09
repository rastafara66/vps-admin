import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import '../models.dart';

enum SshStatus { disconnected, connecting, connected, error }

class CommandResult {
  final String stdout;
  final String stderr;
  final int? exitCode;
  CommandResult(this.stdout, this.stderr, this.exitCode);

  bool get ok => exitCode == 0;

  /// Об'єднаний вивід для показу в UI.
  String get combined {
    final out = stdout.trimRight();
    final err = stderr.trimRight();
    if (err.isEmpty) return out;
    if (out.isEmpty) return err;
    return '$out\n$err';
  }
}

/// Мітка коду завершення в останньому рядку stdout (див. [wrapForExitCode]).
const exitCodeMark = '__VPSADMIN_EXIT_';

/// Команда, яка сама друкує свій код завершення останнім рядком stdout.
///
/// dartssh2 (2.18–2.22) ставить обробник запитів каналу лише ПІСЛЯ відповіді
/// на exec, і швидка команда встигає надіслати exit-status раніше — код
/// губиться (09.11.2026 наживо: 19 з 40 команд, «exit null» у Швидких діях).
/// Підоболонка `( … )` — щоб і `exit 3` дав свій код; переведення рядків —
/// щоб коментар у кінці команди не з'їв дужку.
String wrapForExitCode(String command) =>
    "(\n$command\n)\nprintf '\\n$exitCodeMark%d\\n' \"\$?\"";

/// Вирізає мітку [wrapForExitCode] з кінця stdout. Вивід повертається
/// дослівно таким, яким його дала команда; без мітки код — null.
({String stdout, int? exitCode}) takeExitCode(String stdout) {
  final m = RegExp('\n$exitCodeMark(\\d+)\n?\$').firstMatch(stdout);
  if (m == null) return (stdout: stdout, exitCode: null);
  return (stdout: stdout.substring(0, m.start), exitCode: int.parse(m[1]!));
}

/// Тримає одне активне SSH-з'єднання з активним сервером.
/// Дає: одноразовий exec (для Інфо/Швидких дій), інтерактивний shell
/// (для Терміналу) та SFTP (для Файлів).
class SshService extends ChangeNotifier {
  SshStatus _status = SshStatus.disconnected;
  String? _error;
  String? _connectedServerId;
  SSHClient? _client;
  String? _banner;
  bool _connectionLost = false;

  SshStatus get status => _status;
  String? get error => _error;
  String? get banner => _banner;
  String? get connectedServerId => _connectedServerId;
  bool get isConnected => _status == SshStatus.connected && _client != null;

  /// З'єднання обірвалось само (мережа, сон телефона, перезавантаження сервера),
  /// а не закрите кнопкою. Скидається при наступному підключенні.
  bool get connectionLost => _connectionLost;

  void _set(SshStatus s, {String? error}) {
    _status = s;
    _error = error;
    notifyListeners();
  }

  /// Підключитися до сервера. Якщо вже підключені до іншого — перепідключаємось.
  Future<void> connect(ServerProfile server, ServerSecret? secret) async {
    if (isConnected && _connectedServerId == server.id) return;
    await disconnect();
    _connectionLost = false;
    _set(SshStatus.connecting);
    try {
      final socket = await SSHSocket.connect(
        server.host,
        server.port,
        timeout: const Duration(seconds: 15),
      );

      List<SSHKeyPair>? identities;
      if (server.auth == AuthType.key) {
        final pem = secret?.privateKeyPem;
        if (pem == null || pem.trim().isEmpty) {
          throw 'Для цього сервера не заданий приватний ключ. '
              'Додайте його: вкладка «Сервери» → редагувати → SSH-ключ.';
        }
        identities = SSHKeyPair.fromPem(pem, secret?.passphrase);
      }

      final password = server.auth == AuthType.password ? secret?.password : null;
      if (server.auth == AuthType.password &&
          (password == null || password.isEmpty)) {
        throw 'Для цього сервера не заданий пароль. '
            'Додайте його у налаштуваннях сервера.';
      }

      final client = SSHClient(
        socket,
        username: server.username,
        identities: identities,
        onPasswordRequest: password == null ? null : () => password,
      );

      await client.authenticated;
      _client = client;
      _connectedServerId = server.id;
      _banner = client.remoteVersion;
      // Без цього обірване з'єднання виглядало б живим: вкладки показували б
      // термінал, а кожна команда падала б. Тепер UI пропонує підключитися знову.
      unawaited(client.done.then(
        (_) => _onClientClosed(client),
        onError: (_) => _onClientClosed(client),
      ));
      _set(SshStatus.connected);
    } catch (e) {
      _client = null;
      _connectedServerId = null;
      _set(SshStatus.error, error: _humanize(e));
    }
  }

  /// Транспорт закрився. Якщо це не наше власне [disconnect] (тоді _client
  /// уже інший або null) — позначаємо обрив.
  void _onClientClosed(SSHClient client) {
    if (!identical(_client, client)) return;
    _client = null;
    _connectedServerId = null;
    _banner = null;
    _connectionLost = true;
    _set(SshStatus.disconnected);
  }

  Future<void> disconnect() async {
    final c = _client;
    _client = null;
    _connectedServerId = null;
    _banner = null;
    if (c != null) {
      try {
        c.close();
      } catch (_) {}
    }
    if (_status != SshStatus.disconnected) {
      _set(SshStatus.disconnected);
    }
  }

  SSHClient get _requireClient {
    final c = _client;
    if (c == null || _status != SshStatus.connected) {
      throw 'Немає активного SSH-з\'єднання.';
    }
    return c;
  }

  /// Одноразова команда. Повертає stdout/stderr/exitCode.
  /// Код завершення друкує сама оболонка (див. [wrapForExitCode]).
  Future<CommandResult> exec(String command) async {
    final session = await _requireClient.execute(wrapForExitCode(command));
    final out = <int>[];
    final err = <int>[];
    await Future.wait([
      session.stdout.forEach(out.addAll),
      session.stderr.forEach(err.addAll),
    ]);
    await session.done;
    final res = takeExitCode(utf8.decode(out, allowMalformed: true));
    return CommandResult(
      res.stdout,
      utf8.decode(err, allowMalformed: true),
      // Без мітки (оболонку вбито, з'єднання обірвалось) — що дав SSH.
      res.exitCode ?? session.exitCode,
    );
  }

  /// Запустити кілька команд послідовно й зібрати їх у мапу «команда → результат».
  Future<Map<String, CommandResult>> execAll(List<String> commands) async {
    final result = <String, CommandResult>{};
    for (final c in commands) {
      try {
        result[c] = await exec(c);
      } catch (e) {
        result[c] = CommandResult('', _humanize(e), -1);
      }
    }
    return result;
  }

  /// Інтерактивний shell (для терміналу).
  Future<SSHSession> startShell({
    required int width,
    required int height,
  }) {
    return _requireClient.shell(
      pty: SSHPtyConfig(width: width, height: height),
    );
  }

  /// SFTP-клієнт (для вкладки «Файли»).
  Future<SftpClient> sftp() => _requireClient.sftp();

  String _humanize(Object e) {
    final s = e.toString();
    if (s.contains('SSHAuthFailError') || s.contains('All authentication')) {
      return 'Не вдалась автентифікація: перевірте логін/ключ/пароль.';
    }
    if (s.contains('SocketException') || s.contains('timed out')) {
      return 'Не вдалось з\'єднатися з хостом (мережа / IP / порт / firewall).';
    }
    return s.replaceFirst('Exception: ', '');
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}

/// Хелпер для безпечного декодування байтів SFTP у рядок.
String bytesToString(Uint8List data) => utf8.decode(data, allowMalformed: true);
