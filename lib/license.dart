import 'package:flutter/foundation.dart';

/// Рівень ліцензії.
enum LicenseTier { free, pro }

/// Право доступу (entitlement), отримане від бекенда й кешоване локально.
class Entitlement {
  final LicenseTier tier;
  final String? email;
  final DateTime? expires; // null = безстроково
  final DateTime checkedAt;

  const Entitlement({
    required this.tier,
    this.email,
    this.expires,
    required this.checkedAt,
  });

  static Entitlement free() =>
      Entitlement(tier: LicenseTier.free, checkedAt: DateTime.now());

  bool get isPro => tier == LicenseTier.pro && !isExpired;
  bool get isExpired =>
      expires != null && DateTime.now().isAfter(expires!);

  Map<String, dynamic> toJson() => {
        'tier': tier.name,
        'email': email,
        'expires': expires?.toIso8601String(),
        'checkedAt': checkedAt.toIso8601String(),
      };

  factory Entitlement.fromJson(Map<String, dynamic> j) => Entitlement(
        tier: j['tier'] == 'pro' ? LicenseTier.pro : LicenseTier.free,
        email: j['email'] as String?,
        expires: (j['expires'] as String?) != null
            ? DateTime.tryParse(j['expires'] as String)
            : null,
        checkedAt:
            DateTime.tryParse(j['checkedAt'] as String? ?? '') ?? DateTime.now(),
      );
}

/// Результат спроби активації.
class ActivationResult {
  final bool ok;
  final String? error; // локалізований/сирий код помилки
  const ActivationResult(this.ok, [this.error]);
}

/// Інтерфейс ліцензування. Публічне ядро використовує [FreeLicenseService];
/// офіційна збірка підставляє приватний `ProLicenseService` (lib/pro/).
abstract class LicenseService extends ChangeNotifier {
  Entitlement get entitlement;
  bool get isPro => entitlement.isPro;

  /// Скільки серверів дозволено (free = 1, pro = без обмежень).
  int get maxServers => isPro ? 1000000 : 1;

  /// Чи можна підтримує цей білд активацію Pro (тобто наявний приватний модуль).
  bool get supportsActivation;

  Future<void> init();

  /// Активувати ключ (тільки якщо supportsActivation).
  Future<ActivationResult> activate(String key) async =>
      const ActivationResult(false, 'not_supported');

  /// Скинути ліцензію до free (вихід).
  Future<void> deactivate() async {}
}

/// Безкоштовне ядро: завжди free, 1 сервер, без активації.
/// САМЕ ЦЯ реалізація йде в публічний open-core репозиторій.
class FreeLicenseService extends LicenseService {
  @override
  Entitlement get entitlement => Entitlement.free();

  @override
  bool get supportsActivation => false;

  @override
  Future<void> init() async {}
}
