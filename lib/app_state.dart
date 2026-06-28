import 'package:flutter/material.dart';

import 'license.dart';
import 'models.dart';
import 'seed_data.dart';
import 'services/ai_service.dart';
import 'services/ssh_service.dart';
import 'services/store.dart';

/// Центральний стан застосунку: список серверів, активний сервер,
/// налаштування та координація з SSH-сервісом.
class AppState extends ChangeNotifier {
  final Store store;
  final SshService ssh;
  final LicenseService license;

  List<ServerProfile> _servers = [];
  String? _activeId;
  bool _biometricLock = false;
  AiProvider _aiProvider = AiProvider.anthropic;
  String _localeCode = ''; // '' = за системою, інакше 'en' / 'uk'
  ThemeMode _themeMode = ThemeMode.system;
  int _homeTab = 0; // активна вкладка нижньої навігації

  AppState(this.store, this.ssh, this.license);

  /// Чи можна додати ще один сервер (free = 1, pro = без обмежень).
  bool get canAddServer => _servers.length < license.maxServers;

  List<ServerProfile> get servers => List.unmodifiable(_servers);
  String? get activeId => _activeId;
  bool get biometricLock => _biometricLock;
  AiProvider get aiProvider => _aiProvider;
  String get localeCode => _localeCode;
  ThemeMode get themeMode => _themeMode;
  int get homeTab => _homeTab;

  /// Перейти на вкладку нижньої навігації (0=Сервери,1=Інфо,2=Термінал,…).
  void goToTab(int index) {
    if (_homeTab == index) return;
    _homeTab = index;
    notifyListeners();
  }

  ServerProfile? get activeServer {
    if (_activeId == null) return null;
    for (final s in _servers) {
      if (s.id == _activeId) return s;
    }
    return null;
  }

  bool get isActiveConnected =>
      ssh.isConnected && ssh.connectedServerId == _activeId;

  Future<void> init() async {
    if (!store.isSeeded) {
      _servers = seedServers();
      await store.saveProfiles(_servers);
      await store.markSeeded();
    } else {
      _servers = store.loadProfiles();
    }
    _activeId = store.activeId ?? (_servers.isNotEmpty ? _servers.first.id : null);
    _biometricLock = store.biometricLock;
    _aiProvider = AiProviderX.fromWire(store.aiProvider);
    _localeCode = store.localeCode;
    _themeMode = _parseThemeMode(store.themeMode);
    notifyListeners();
  }


  // ── Сервери ──────────────────────────────────────────────────────────
  Future<void> upsertServer(ServerProfile profile, {ServerSecret? secret}) async {
    final i = _servers.indexWhere((s) => s.id == profile.id);
    if (i >= 0) {
      _servers[i] = profile;
    } else {
      _servers.add(profile);
    }
    await store.saveProfiles(_servers);
    if (secret != null) {
      await store.saveSecret(profile.id, secret);
    }
    _activeId ??= profile.id;
    await store.setActiveId(_activeId);
    notifyListeners();
  }

  Future<void> deleteServer(String id) async {
    _servers.removeWhere((s) => s.id == id);
    await store.deleteSecret(id);
    if (_activeId == id) {
      _activeId = _servers.isNotEmpty ? _servers.first.id : null;
      await store.setActiveId(_activeId);
      await ssh.disconnect();
    }
    await store.saveProfiles(_servers);
    notifyListeners();
  }

  Future<void> setActive(String id) async {
    if (_activeId == id) return;
    _activeId = id;
    await store.setActiveId(id);
    await ssh.disconnect();
    notifyListeners();
  }

  Future<ServerSecret?> secretFor(String id) => store.loadSecret(id);

  /// Підключитися до активного сервера.
  Future<void> connectActive() async {
    final s = activeServer;
    if (s == null) return;
    final secret = await store.loadSecret(s.id);
    await ssh.connect(s, secret);
  }

  // ── Налаштування ─────────────────────────────────────────────────────
  Future<void> setBiometricLock(bool v) async {
    _biometricLock = v;
    await store.setBiometricLock(v);
    notifyListeners();
  }

  // ── AI-провайдер ───────────────────────────────────────────────────────
  Future<void> setAiProvider(AiProvider p) async {
    _aiProvider = p;
    await store.setAiProvider(p.wire);
    notifyListeners();
  }

  /// Модель для провайдера (із дефолтом, якщо не задано).
  String aiModel(AiProvider p) {
    final m = store.aiModel(p.wire);
    return m.isEmpty ? p.defaultModel : m;
  }

  Future<void> setAiModel(AiProvider p, String model) async {
    await store.setAiModel(p.wire, model.trim());
    notifyListeners();
  }

  Future<String?> aiKey(AiProvider p) => store.loadAiKey(p.wire);
  Future<void> setAiKey(AiProvider p, String key) =>
      store.saveAiKey(p.wire, key.trim());

  String get aiBaseUrl => store.aiBaseUrl;
  Future<void> setAiBaseUrl(String v) async {
    await store.setAiBaseUrl(v.trim());
    notifyListeners();
  }

  /// Зібрати клієнт активного AI-провайдера (null, якщо ключ не заданий).
  Future<AiClient?> aiClient() async {
    final p = _aiProvider;
    final key = await store.loadAiKey(p.wire);
    if (key == null || key.trim().isEmpty) return null;
    return AiClient(
      provider: p,
      apiKey: key.trim(),
      model: aiModel(p),
      baseUrl: p.needsBaseUrl ? store.aiBaseUrl : null,
    );
  }

  /// Мова додатка: '' = за системою, 'en' / 'uk' = примусово.
  Future<void> setLocaleCode(String code) async {
    _localeCode = code;
    await store.setLocaleCode(code);
    notifyListeners();
  }

  /// Тема: system / light / dark.
  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await store.setThemeMode(mode.name);
    notifyListeners();
  }

  static ThemeMode _parseThemeMode(String s) => switch (s) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

}
