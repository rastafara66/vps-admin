import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../services/ssh_service.dart';
import '../widgets.dart';

/// Дашборд активного сервера: набір SSH-команд → картки з виводом.
class InfoTab extends StatelessWidget {
  const InfoTab({super.key});

  @override
  Widget build(BuildContext context) {
    return RequireConnection(builder: (context) => const _Dashboard());
  }
}

class _Metric {
  final IconData icon;
  final String command;
  final String Function(AppLocalizations l) title;
  const _Metric(this.icon, this.command, this.title);
}

final _metrics = <_Metric>[
  _Metric(Icons.computer,
      'echo "Host: \$(hostname)"; echo "Kernel: \$(uname -srm)"; echo "Distro: \$(. /etc/os-release 2>/dev/null; echo \$PRETTY_NAME)"',
      (l) => l.metricSystem),
  _Metric(Icons.timelapse, 'uptime', (l) => l.metricUptime),
  _Metric(Icons.memory, 'free -h', (l) => l.metricMemory),
  _Metric(Icons.storage, 'df -h -x tmpfs -x devtmpfs', (l) => l.metricDisk),
  _Metric(Icons.speed,
      'ps -eo pid,pcpu,pmem,comm --sort=-pcpu | head -n 8', (l) => l.metricTopCpu),
  _Metric(Icons.developer_board,
      'docker ps --format "table {{.Names}}\\t{{.Status}}\\t{{.Ports}}" 2>/dev/null || echo "docker n/a"',
      (l) => l.metricDocker),
];

class _Dashboard extends StatefulWidget {
  const _Dashboard();

  @override
  State<_Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<_Dashboard> {
  Map<String, CommandResult> _data = {};
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final ssh = context.read<SshService>();
    final data = await ssh.execAll(_metrics.map((m) => m.command).toList());
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 88, top: 4),
        children: [
          if (_loading) const LinearProgressIndicator(),
          for (final m in _metrics)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(m.icon, size: 18,
                            color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(m.title(l),
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    MonoOutput(_data[m.command]?.combined.trim().isNotEmpty == true
                        ? _data[m.command]!.combined.trim()
                        : (_loading ? '…' : '—')),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
