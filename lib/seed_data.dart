import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'models.dart';

/// Публічне ядро стартує без передзаповнених серверів — користувач додає свій.
List<ServerProfile> seedServers() => const [];

/// Швидкі дії = поширені стандартні команди адміністрування Linux-сервера.
List<QuickAction> seedQuickActions(AppLocalizations l) => commonQuickActions(l);

/// Поширені стандартні дії адміністрування Linux-сервера (для будь-якого VPS).
List<QuickAction> commonQuickActions(AppLocalizations l) => [
      QuickAction(title: l.metricDisk, description: 'df -h', command: 'df -h'),
      QuickAction(title: l.metricMemory, description: 'free -h', command: 'free -h'),
      QuickAction(title: l.metricUptime, description: 'uptime', command: 'uptime'),
      QuickAction(
          title: l.metricTopCpu,
          description: 'ps aux --sort=-%cpu | head',
          command: 'ps aux --sort=-%cpu | head -n 12'),
      QuickAction(
          title: l.qaTopMem,
          description: 'ps aux --sort=-%mem | head',
          command: 'ps aux --sort=-%mem | head -n 12'),
      QuickAction(
          title: l.qaPorts,
          description: 'ss -tulpn',
          command: 'ss -tulpn 2>/dev/null || netstat -tulpn'),
      QuickAction(
          title: l.qaFailed,
          description: 'systemctl --failed',
          command: 'systemctl --failed --no-pager'),
      QuickAction(
          title: l.qaLastLogins, description: 'last -n 20', command: 'last -n 20'),
      QuickAction(
          title: l.qaPublicIp,
          description: 'curl ifconfig.me',
          command: 'curl -s ifconfig.me || curl -s ipinfo.io/ip'),
      QuickAction(
          title: l.qaUpdates,
          description: 'apt list --upgradable',
          command: 'apt list --upgradable 2>/dev/null | tail -n +2 | head -n 40'),
      QuickAction(
          title: l.qaUpgrade,
          description: 'apt update && apt upgrade -y',
          command: 'sudo apt update && sudo apt -y upgrade',
          dangerous: true),
      QuickAction(
          title: l.qaReboot,
          description: 'sudo reboot',
          command: 'sudo reboot',
          dangerous: true),
    ];
