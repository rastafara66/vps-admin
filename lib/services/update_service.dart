import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Інформація про доступне оновлення.
class UpdateInfo {
  final String version; // напр. "1.0.7"
  final String apkUrl;
  final String notes;
  const UpdateInfo(
      {required this.version, required this.apkUrl, required this.notes});
}

/// Перевірка нових версій через GitHub Releases + завантаження/встановлення APK.
class UpdateService {
  static const _repo = 'rastafara66/vps-admin';

  /// Поточна версія застосунку (versionName з pubspec).
  static Future<String> currentVersion() async =>
      (await PackageInfo.fromPlatform()).version;

  /// Перевірити, чи є новіший реліз. null = немає / помилка.
  static Future<UpdateInfo?> check() async {
    try {
      final resp = await http.get(
        Uri.parse('https://api.github.com/repos/$_repo/releases/latest'),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return null;

      final j = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final tag = (j['tag_name'] as String? ?? '').replaceFirst('v', '').trim();
      if (tag.isEmpty) return null;

      String? apkUrl;
      for (final a in (j['assets'] as List? ?? const [])) {
        final name = (a as Map)['name'] as String? ?? '';
        if (name.toLowerCase().endsWith('.apk')) {
          apkUrl = a['browser_download_url'] as String?;
          break;
        }
      }
      if (apkUrl == null) return null;

      final current = await currentVersion();
      if (!_isNewer(tag, current)) return null;

      return UpdateInfo(
        version: tag,
        apkUrl: apkUrl,
        notes: (j['body'] as String? ?? '').trim(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Завантажити APK (з прогресом 0..1) і відкрити системний інсталер.
  static Future<void> downloadAndInstall(
    UpdateInfo info, {
    void Function(double progress)? onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/vps-admin-${info.version}.apk');

    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(info.apkUrl));
      final resp = await client.send(req);
      final total = resp.contentLength ?? 0;
      var received = 0;
      final sink = file.openWrite();
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
      await sink.close();
    } finally {
      client.close();
    }

    // Відкриває системний інсталер пакетів (користувач підтверджує встановлення).
    await OpenFilex.open(file.path,
        type: 'application/vnd.android.package-archive');
  }

  /// Порівняння версій за SemVer-логікою: чи `a` новіша за `b`.
  /// Числове ядро "x.y.z" порівнюється покомпонентно; за рівного ядра
  /// стабільна версія ("1.0.0") вважається новішою за pre-release
  /// тієї ж версії ("1.0.0-beta"). Build-метадані ("+6") ігноруються.
  static bool _isNewer(String a, String b) {
    (List<int>, bool) parse(String s) {
      final cut = s.indexOf(RegExp(r'[-+]'));
      final hasPre = cut >= 0 && s[cut] == '-';
      final core = cut < 0 ? s : s.substring(0, cut);
      final nums =
          core.split('.').map((e) => int.tryParse(e.trim()) ?? 0).toList();
      return (nums, hasPre);
    }

    final (na, preA) = parse(a);
    final (nb, preB) = parse(b);
    for (var i = 0; i < na.length || i < nb.length; i++) {
      final x = i < na.length ? na[i] : 0;
      final y = i < nb.length ? nb[i] : 0;
      if (x != y) return x > y;
    }
    // Ядро однакове: стабільна (без pre-release) новіша за pre-release.
    if (preA != preB) return !preA;
    return false;
  }
}
