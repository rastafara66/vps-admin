import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'models.dart';

/// Публічне ядро стартує без передзаповнених серверів — користувач додає свій.
List<ServerProfile> seedServers() => const [];

/// Швидкі дії = поширені стандартні команди адміністрування Linux-сервера.
List<QuickAction> seedQuickActions(AppLocalizations l) => commonQuickActions(l);

/// Поширені стандартні дії адміністрування Linux-сервера (для будь-якого VPS).
List<QuickAction> commonQuickActions(AppLocalizations l) => [
      QuickAction(title: l.metricDisk, description: 'df -h', command: 'df -h', group: l.grpSystem),
      QuickAction(title: l.metricMemory, description: 'free -h', command: 'free -h', group: l.grpSystem),
      QuickAction(title: l.metricUptime, description: 'uptime', command: 'uptime', group: l.grpSystem),
      QuickAction(title: l.metricTopCpu, description: 'ps aux --sort=-%cpu | head', command: 'ps aux --sort=-%cpu | head -n 12', group: l.grpSystem),
      QuickAction(title: l.qaTopMem, description: 'ps aux --sort=-%mem | head', command: 'ps aux --sort=-%mem | head -n 12', group: l.grpSystem),
      QuickAction(title: l.qaDockerTitle, description: 'docker ps', command: 'docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"', group: l.grpSystem),
      QuickAction(title: l.qaPorts, description: 'ss -tulpn', command: 'ss -tulpn 2>/dev/null || netstat -tulpn', group: l.grpSystem),
      QuickAction(title: l.qaFailed, description: 'systemctl --failed', command: 'systemctl --failed --no-pager', group: l.grpSystem),
      QuickAction(title: l.qaLastLogins, description: 'last -n 20', command: 'last -n 20', group: l.grpSystem),
      QuickAction(title: l.qaPublicIp, description: 'curl ifconfig.me', command: 'curl -s ifconfig.me || curl -s ipinfo.io/ip', group: l.grpSystem),
      QuickAction(title: l.qaUpdates, description: 'apt list --upgradable', command: 'apt list --upgradable 2>/dev/null | tail -n +2 | head -n 40', group: l.grpMaintenance),
      QuickAction(title: l.qaUpgrade, description: 'apt update && apt upgrade -y', command: 'sudo apt update && sudo apt -y upgrade', dangerous: true, group: l.grpMaintenance),
      QuickAction(title: l.qaReboot, description: 'sudo reboot', command: 'sudo reboot', dangerous: true, group: l.grpMaintenance),
      QuickAction(title: l.qaCron, description: 'crontab -l', command: 'crontab -l 2>/dev/null || echo "${l.msgCronEmpty}"', group: l.grpMaintenance),
      ...sessionQuickActions(l),
    ];

/// Постійні сесії: термінал, який живе на сервері й переживає закриття
/// застосунку (tmux). Назви сесій і програми в ній — справа користувача,
/// тут лише загальні кроки.
List<QuickAction> sessionQuickActions(AppLocalizations l) => [
      QuickAction(
        title: l.qaTmuxCheck,
        description: 'tmux -V',
        command: 'if command -v tmux >/dev/null 2>&1; then tmux -V; else echo "${l.msgTmuxMissing}"; fi',
        group: l.grpSessions,
      ),
      QuickAction(
        title: l.qaTmuxInstall,
        description: 'apt / dnf / yum / apk / pacman install tmux',
        command: installPackageCommand('tmux'),
        dangerous: true,
        group: l.grpSessions,
      ),
      QuickAction(
        title: l.qaTmuxMouse,
        description: "echo 'set -g mouse on' >> ~/.tmux.conf",
        command: "touch ~/.tmux.conf && (grep -qxF 'set -g mouse on' ~/.tmux.conf || echo 'set -g mouse on' >> ~/.tmux.conf) && (tmux source-file ~/.tmux.conf 2>/dev/null; true) && echo 'OK: set -g mouse on'",
        group: l.grpSessions,
      ),
      QuickAction(
        title: l.qaTmuxList,
        description: 'tmux ls',
        command: 'tmux ls 2>/dev/null || echo "${l.msgTmuxNoSessions}"',
        group: l.grpSessions,
      ),
    ];

/// Встановити пакет тим менеджером пакетів, який є на сервері
/// (Debian/Ubuntu, Fedora/RHEL, Alpine, Arch). Без sudo, якщо ми root.
String installPackageCommand(String pkg) =>
    'S=""; [ "\$(id -u)" -ne 0 ] && S="sudo"; '
    'if command -v apt-get >/dev/null 2>&1; then \$S apt-get update -qq && \$S env DEBIAN_FRONTEND=noninteractive apt-get install -y $pkg; '
    'elif command -v dnf >/dev/null 2>&1; then \$S dnf install -y $pkg; '
    'elif command -v yum >/dev/null 2>&1; then \$S yum install -y $pkg; '
    'elif command -v apk >/dev/null 2>&1; then \$S apk add $pkg; '
    'elif command -v pacman >/dev/null 2>&1; then \$S pacman -S --noconfirm $pkg; '
    'else echo "no supported package manager (apt, dnf, yum, apk, pacman)"; exit 1; fi';
