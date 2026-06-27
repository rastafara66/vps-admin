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

/// Тримає одне активне SSH-з'єднання з активним сервером.
/// Дає: одноразовий exec (для Інфо/Швидких дій), інтерактивний shell
/// (для Терміналу) та SFTP (для Файлів).
class SshService extends ChangeNotifier {
  SshStatus _status = SshStatus.disconnected;
  String? _error;
  String? _connectedServerId;
  SSHClient? _client;
  String? _banner;

  SshStatus get status => _status;
  String? get error => _error;
  String? get banner => _banner;
  String? get connectedServerId => _connectedServerId;
  bool get isConnected => _status == SshStatus.connected && _client != null;

  void _set(SshStatus s, {String? error}) {
    _status = s;
    _error = error;
    notifyListeners();
  }

  /// Підключитися до сервера. Якщо вже підключені до іншого — перепідключаємось.
  Future<void> connect(ServerProfile server, ServerSecret? secret) async {
    if (isConnected && _connectedServerId == server.id) return;
    await disconnect();
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
      _set(SshStatus.connected);
    } catch (e) {
      _client = null;
      _connectedServerId = null;
      _set(SshStatus.error, error: _humanize(e));
    }
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
  Future<CommandResult> exec(String command) async {
    final session = await _requireClient.execute(command);
    final out = <int>[];
    final err = <int>[];
    await Future.wait([
      session.stdout.forEach(out.addAll),
      session.stderr.forEach(err.addAll),
    ]);
    await session.done;
    return CommandResult(
      utf8.decode(out, allowMalformed: true),
      utf8.decode(err, allowMalformed: true),
      session.exitCode,
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
