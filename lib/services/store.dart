import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models.dart';

/// Сховище: нечутливі дані → SharedPreferences (JSON),
/// секрети (паролі, приватні ключі, API-ключ Claude) → flutter_secure_storage.
class Store {
  static const _kProfiles = 'profiles';
  static const _kActiveId = 'active_server_id';
  static const _kSeeded = 'seeded_v1';
  static const _kBiometric = 'biometric_lock';
  static const _kClaudeModel = 'claude_model';
  static const _kLocale = 'app_locale';
  static const _kThemeMode = 'theme_mode';

  static const _kSecretPrefix = 'secret_';
  static const _kClaudeApiKey = 'claude_api_key';
  static const _kDeviceId = 'device_id';
  static const _kLicenseKey = 'license_key';
  static const _kEntitlement = 'entitlement';

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;

  Store(this._prefs, this._secure);

  static Future<Store> open() async {
    final prefs = await SharedPreferences.getInstance();
    const secure = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    );
    return Store(prefs, secure);
  }

  // ── Профілі ────────────────────────────────────────────────────────────
  bool get isSeeded => _prefs.getBool(_kSeeded) ?? false;
  Future<void> markSeeded() => _prefs.setBool(_kSeeded, true);

  List<ServerProfile> loadProfiles() {
    final raw = _prefs.getString(_kProfiles);
    if (raw == null || raw.isEmpty) return [];
    final list = (jsonDecode(raw) as List)
        .map((e) => ServerProfile.fromJson(e as Map<String, dynamic>))
        .toList();
    return list;
  }

  Future<void> saveProfiles(List<ServerProfile> profiles) {
    final raw = jsonEncode(profiles.map((e) => e.toJson()).toList());
    return _prefs.setString(_kProfiles, raw);
  }

  String? get activeId => _prefs.getString(_kActiveId);
  Future<void> setActiveId(String? id) async {
    if (id == null) {
      await _prefs.remove(_kActiveId);
    } else {
      await _prefs.setString(_kActiveId, id);
    }
  }

  // ── Налаштування ───────────────────────────────────────────────────────
  bool get biometricLock => _prefs.getBool(_kBiometric) ?? false;
  Future<void> setBiometricLock(bool v) => _prefs.setBool(_kBiometric, v);

  String get claudeModel =>
      _prefs.getString(_kClaudeModel) ?? 'claude-opus-4-8';
  Future<void> setClaudeModel(String v) => _prefs.setString(_kClaudeModel, v);

  // '' = за системою (default), 'en' / 'uk' = примусово
  String get localeCode => _prefs.getString(_kLocale) ?? '';
  Future<void> setLocaleCode(String v) => _prefs.setString(_kLocale, v);

  // 'system' (default) | 'light' | 'dark'
  String get themeMode => _prefs.getString(_kThemeMode) ?? 'system';
  Future<void> setThemeMode(String v) => _prefs.setString(_kThemeMode, v);

  // ── Секрети ────────────────────────────────────────────────────────────
  Future<ServerSecret?> loadSecret(String serverId) async {
    final raw = await _secure.read(key: '$_kSecretPrefix$serverId');
    if (raw == null || raw.isEmpty) return null;
    return ServerSecret.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveSecret(String serverId, ServerSecret secret) =>
      _secure.write(
        key: '$_kSecretPrefix$serverId',
        value: jsonEncode(secret.toJson()),
      );

  Future<void> deleteSecret(String serverId) =>
      _secure.delete(key: '$_kSecretPrefix$serverId');

  Future<String?> loadClaudeApiKey() => _secure.read(key: _kClaudeApiKey);
  Future<void> saveClaudeApiKey(String key) =>
      _secure.write(key: _kClaudeApiKey, value: key);

  // ── Ліцензія ─────────────────────────────────────────────────────────
  /// Стабільний ідентифікатор пристрою (для прив'язки активацій).
  String deviceId() {
    var id = _prefs.getString(_kDeviceId);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      _prefs.setString(_kDeviceId, id);
    }
    return id;
  }

  Future<String?> loadLicenseKey() => _secure.read(key: _kLicenseKey);
  Future<void> saveLicenseKey(String key) =>
      _secure.write(key: _kLicenseKey, value: key);

  String? loadEntitlementRaw() => _prefs.getString(_kEntitlement);
  Future<void> saveEntitlementRaw(String json) =>
      _prefs.setString(_kEntitlement, json);

  Future<void> clearLicense() async {
    await _secure.delete(key: _kLicenseKey);
    await _prefs.remove(_kEntitlement);
  }
}
