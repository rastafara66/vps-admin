import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../services/ssh_service.dart';
import '../widgets.dart';
import 'action_edit_screen.dart';

/// Швидкі дії: вбудовані + користувацькі, з теками й пошуком.
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
  String _query = '';
  final Set<String> _collapsed = {};

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

  Future<void> _editAction(QuickAction? a) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ActionEditScreen(existing: a)),
    );
  }

  Future<void> _deleteAction(QuickAction a) async {
    final l = AppLocalizations.of(context);
    final app = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l.deleteAction),
        content: Text(a.title),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.delete)),
        ],
      ),
    );
    if (ok == true && a.id != null) {
      await app.deleteCustomAction(a.id!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final app = context.watch<AppState>();
    final all = app.quickActions(l);
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? all
        : all
            .where((a) =>
                a.title.toLowerCase().contains(q) ||
                a.command.toLowerCase().contains(q) ||
                a.group.toLowerCase().contains(q))
            .toList();

    return Scaffold(
      body: Column(
        children: [
          if (all.length > 5)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: l.searchActions,
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 88, top: 4),
              children: [
                if (filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(child: Text(l.nothingFound)),
                  ),
                ..._grouped(context, l, filtered),
                if (_result != null) _resultBlock(l),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editAction(null),
        icon: const Icon(Icons.add),
        label: Text(l.addAction),
      ),
    );
  }

  List<Widget> _grouped(
      BuildContext context, AppLocalizations l, List<QuickAction> list) {
    final groups = <String, List<QuickAction>>{};
    for (final a in list) {
      groups.putIfAbsent(a.group, () => []).add(a);
    }
    final keys = groups.keys.toList()
      ..sort((a, b) {
        if (a.isEmpty) return 1;
        if (b.isEmpty) return -1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
    final showHeaders = !(keys.length == 1 && keys.first.isEmpty);
    final widgets = <Widget>[];
    for (final k in keys) {
      final collapsed = _collapsed.contains(k);
      if (showHeaders) {
        widgets.add(GroupHeader(
          text: k.isEmpty ? l.noFolder : k,
          count: groups[k]!.length,
          collapsed: collapsed,
          onTap: () => setState(
              () => collapsed ? _collapsed.remove(k) : _collapsed.add(k)),
        ));
      }
      if (!showHeaders || !collapsed) {
        for (final a in groups[k]!) {
          widgets.add(_actionCard(context, l, a));
        }
      }
    }
    return widgets;
  }

  Widget _actionCard(BuildContext context, AppLocalizations l, QuickAction a) {
    final running = _runningCmd == a.command;
    return Card(
      child: ListTile(
        leading: Icon(
          a.dangerous ? Icons.warning_amber : Icons.bolt,
          color: a.dangerous ? Colors.amber : const Color(0xFF4EC9B0),
        ),
        title: Text(a.title),
        subtitle: Text(a.description,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
        trailing: running
            ? const SizedBox(
                width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : (a.isCustom
                ? PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'edit') _editAction(a);
                      if (v == 'delete') _deleteAction(a);
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 'edit', child: Text(l.edit)),
                      PopupMenuItem(value: 'delete', child: Text(l.delete)),
                    ],
                  )
                : const Icon(Icons.play_arrow)),
        onTap: _runningCmd == null ? () => _run(a) : null,
      ),
    );
  }

  Widget _resultBlock(AppLocalizations l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Icon(_result!.ok ? Icons.check_circle : Icons.error,
                  size: 16,
                  color: _result!.ok
                      ? const Color(0xFF4EC9B0)
                      : Colors.redAccent),
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
          child: MonoOutput(_result!.combined.trim().isEmpty
              ? l.noOutput
              : _result!.combined.trim()),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

