import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../services/ssh_service.dart';
import '../services/update_service.dart';
import '../theme.dart';
import 'ai_tab.dart';
import 'files_tab.dart';
import 'help_screen.dart';
import 'info_tab.dart';
import 'quick_actions_tab.dart';
import 'servers_tab.dart';
import 'settings_screen.dart';
import 'terminal_tab.dart';
import 'update_dialog.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _tabs = const [
    ServersTab(),
    InfoTab(),
    TerminalTab(),
    FilesTab(),
    AiTab(),
    QuickActionsTab(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoCheckUpdates());
  }

  /// Перевірка оновлень при старті (якщо не вимкнено в налаштуваннях).
  Future<void> _autoCheckUpdates() async {
    if (!mounted) return;
    final app = context.read<AppState>();
    if (app.updateMode == 'off') return;
    final info = await UpdateService.check();
    if (info == null || !mounted) return;
    await showUpdateDialog(context, info, autoStart: app.updateMode == 'auto');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final ssh = context.watch<SshService>();
    final active = app.activeServer;
    final l = AppLocalizations.of(context);
    final index = app.homeTab;
    final titles = [
      l.titleServers,
      l.titleInfo,
      l.titleTerminal,
      l.titleFiles,
      l.titleAi,
      l.titleQuickActions,
    ];

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titles[index], style: const TextStyle(fontSize: 16)),
            if (active != null)
              Text(
                active.name,
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
          ],
        ),
        actions: [
          _ConnButton(app: app, ssh: ssh),
          IconButton(
            tooltip: l.help,
            icon: const Icon(Icons.help_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HelpScreen()),
            ),
          ),
          IconButton(
            tooltip: l.settings,
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: IndexedStack(index: index, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: app.goToTab,
        destinations: [
          NavigationDestination(icon: const Icon(Icons.dns_outlined), label: l.titleServers),
          NavigationDestination(icon: const Icon(Icons.monitor_heart_outlined), label: l.titleInfo),
          NavigationDestination(icon: const Icon(Icons.terminal), label: l.titleTerminal),
          NavigationDestination(icon: const Icon(Icons.folder_outlined), label: l.titleFiles),
          NavigationDestination(icon: const Icon(Icons.smart_toy_outlined), label: l.titleAi),
          NavigationDestination(icon: const Icon(Icons.bolt_outlined), label: l.navActions),
        ],
      ),
    );
  }
}

/// Кнопка-індикатор підключення в AppBar.
class _ConnButton extends StatelessWidget {
  final AppState app;
  final SshService ssh;
  const _ConnButton({required this.app, required this.ssh});

  @override
  Widget build(BuildContext context) {
    final connecting = ssh.status == SshStatus.connecting;
    final connected = app.isActiveConnected;
    final color = statusColor(connected, connecting);
    final l = AppLocalizations.of(context);

    return Row(
      children: [
        if (connecting)
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          Icon(Icons.circle, size: 12, color: color),
        IconButton(
          tooltip: connected ? l.disconnect : l.connect,
          icon: Icon(connected ? Icons.link_off : Icons.link),
          onPressed: app.activeServer == null
              ? null
              : () async {
                  if (connected) {
                    await ssh.disconnect();
                  } else {
                    await app.connectActive();
                    final err = ssh.error;
                    if (err != null && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(err)),
                      );
                    }
                  }
                },
        ),
      ],
    );
  }
}
