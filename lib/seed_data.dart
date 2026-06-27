import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'models.dart';

/// Публічне ядро стартує без передзаповнених серверів — користувач додає свій
/// (безкоштовна версія: 1 сервер).
List<ServerProfile> seedServers() => const [];

/// Приклади швидких дій (узагальнені системні команди).
List<QuickAction> seedQuickActions(AppLocalizations l) => [
      QuickAction(title: l.metricDisk, description: 'df -h', command: 'df -h'),
      QuickAction(title: l.metricMemory, description: 'free -h', command: 'free -h'),
      QuickAction(title: l.metricUptime, description: 'uptime', command: 'uptime'),
      QuickAction(
          title: l.qaDockerTitle, description: 'docker ps', command: 'docker ps'),
    ];
