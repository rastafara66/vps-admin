import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../seed_data.dart';
import '../services/ssh_service.dart';
import '../widgets.dart';

/// Готові кнопки під типові задачі Сергія (health, деплой, docker тощо).
class QuickActionsTab extends StatelessWidget {
  const QuickActionsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return RequireConnection(builder: (context) => const _Actions());
  }
}

class _Actions extends StatefulWidget {
  const _Actions();

  @override
  State<_Actions> createState() => _ActionsState();
}

class _ActionsState extends State<_Actions> {
  String? _runningCmd;
  CommandResult? _result;
  QuickAction? _lastAction;

  Future<void> _run(QuickAction a) async {
    final l = AppLocalizations.of(context);
    if (a.dangerous) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Row(children: [
            const Icon(Icons.warning_amber, color: Colors.amber),
            const SizedBox(width: 8),
            Text(l.heavyAction),
          ]),
          content: Text(l.heavyActionBody(a.title, a.description)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l.cancel)),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l.run)),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (!mounted) return;

    final ssh = context.read<SshService>();
    setState(() {
      _runningCmd = a.command;
      _result = null;
      _lastAction = a;
    });
    final res = await ssh.exec(a.command);
    if (!mounted) return;
    setState(() {
      _runningCmd = null;
      _result = res;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: 88, top: 4),
      children: [
        for (final a in seedQuickActions(l))
          Card(
            child: ListTile(
              leading: Icon(
                a.dangerous ? Icons.warning_amber : Icons.bolt,
                color: a.dangerous ? Colors.amber : const Color(0xFF4EC9B0),
              ),
              title: Text(a.title),
              subtitle: Text(a.description,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
              trailing: _runningCmd == a.command
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_arrow),
              onTap: _runningCmd == null ? () => _run(a) : null,
            ),
          ),
        if (_result != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Icon(
                  _result!.ok ? Icons.check_circle : Icons.error,
                  size: 16,
                  color: _result!.ok ? const Color(0xFF4EC9B0) : Colors.redAccent,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l.actionResult(_lastAction?.title ?? '', '${_result!.exitCode}'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: MonoOutput(
              _result!.combined.trim().isEmpty
                  ? l.noOutput
                  : _result!.combined.trim(),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ],
    );
  }
}
