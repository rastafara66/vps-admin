import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Спосіб автентифікації на сервері.
enum AuthType { password, key }

extension AuthTypeX on AuthType {
  String get wire => this == AuthType.password ? 'password' : 'key';
  static AuthType fromWire(String? s) =>
      s == 'password' ? AuthType.password : AuthType.key;
}

/// Профіль одного VPS-сервера. Містить ЛИШЕ нечутливі поля —
/// секрет (пароль / приватний ключ / пасфраза) зберігається окремо
/// у flutter_secure_storage (Android Keystore) і ніколи не лягає у JSON/git.
class ServerProfile {
  final String id;
  String name;
  String host;
  int port;
  String username;
  AuthType auth;
  String defaultDir;

  ServerProfile({
    String? id,
    required this.name,
    required this.host,
    this.port = 22,
    required this.username,
    this.auth = AuthType.key,
    this.defaultDir = '/home/ubuntu',
  }) : id = id ?? _uuid.v4();

  ServerProfile copy() => ServerProfile(
        id: id,
        name: name,
        host: host,
        port: port,
        username: username,
        auth: auth,
        defaultDir: defaultDir,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'username': username,
        'auth': auth.wire,
        'defaultDir': defaultDir,
      };

  factory ServerProfile.fromJson(Map<String, dynamic> j) => ServerProfile(
        id: j['id'] as String?,
        name: j['name'] as String? ?? 'Сервер',
        host: j['host'] as String? ?? '',
        port: (j['port'] as num?)?.toInt() ?? 22,
        username: j['username'] as String? ?? 'root',
        auth: AuthTypeX.fromWire(j['auth'] as String?),
        defaultDir: j['defaultDir'] as String? ?? '/home/ubuntu',
      );

  String get displayTarget => '$username@$host:$port';
}

/// Секрет сервера — тримається лише в secure storage.
class ServerSecret {
  /// Для AuthType.password — пароль; для AuthType.key — не використовується.
  final String? password;

  /// Для AuthType.key — PEM приватного ключа.
  final String? privateKeyPem;

  /// Пасфраза до зашифрованого приватного ключа (опційно).
  final String? passphrase;

  const ServerSecret({this.password, this.privateKeyPem, this.passphrase});

  bool get isEmpty =>
      (password == null || password!.isEmpty) &&
      (privateKeyPem == null || privateKeyPem!.isEmpty);

  Map<String, dynamic> toJson() => {
        if (password != null) 'password': password,
        if (privateKeyPem != null) 'privateKeyPem': privateKeyPem,
        if (passphrase != null) 'passphrase': passphrase,
      };

  factory ServerSecret.fromJson(Map<String, dynamic> j) => ServerSecret(
        password: j['password'] as String?,
        privateKeyPem: j['privateKeyPem'] as String?,
        passphrase: j['passphrase'] as String?,
      );
}

/// Готова «швидка дія» — кнопка з командою.
class QuickAction {
  final String title;
  final String description;
  final String command;

  /// Деструктивна / важка дія — вимагає підтвердження в UI.
  final bool dangerous;

  const QuickAction({
    required this.title,
    required this.description,
    required this.command,
    this.dangerous = false,
  });
}

/// Повідомлення в AI-чаті.
class ChatMessage {
  final String role; // 'user' | 'assistant'
  String text;
  ChatMessage(this.role, this.text);

  Map<String, dynamic> toApi() => {'role': role, 'content': text};
}
