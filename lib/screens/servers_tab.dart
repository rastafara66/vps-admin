import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../services/ssh_service.dart';
import '../widgets.dart';
import 'server_edit_screen.dart';
import 'settings_screen.dart';

class ServersTab extends StatefulWidget {
  const ServersTab({super.key});

  @override
  State<ServersTab> createState() => _ServersTabState();
}

class _ServersTabState extends State<ServersTab> {
  String _query = '';
  final Set<String> _collapsed = {};

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final ssh = context.watch<SshService>();
    final servers = app.servers;
    final l = AppLocalizations.of(context);

    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? servers
        : servers
            .where((s) =>
                s.name.toLowerCase().contains(q) ||
                s.host.toLowerCase().contains(q) ||
                s.group.toLowerCase().contains(q))
            .toList();

    return Scaffold(
      body: servers.isEmpty
          ? const _Empty()
          : Column(
              children: [
                if (servers.length > 3) _SearchField(
                  hint: l.searchServers,
                  onChanged: (v) => setState(() => _query = v),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(child: Text(l.nothingFound))
                      : ListView(
                          padding: const EdgeInsets.only(bottom: 88, top: 4),
                          children: _grouped(context, app, ssh, l, filtered),
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            app.canAddServer ? _edit(context, null) : _showUpgrade(context),
        icon: const Icon(Icons.add),
        label: Text(l.addVps),
      ),
    );
  }

  List<Widget> _grouped(BuildContext context, AppState app, SshService ssh,
      AppLocalizations l, List<ServerProfile> list) {
    final groups = <String, List<ServerProfile>>{};
    for (final s in list) {
      groups.putIfAbsent(s.group, () => []).add(s);
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
        for (final s in groups[k]!) {
          widgets.add(_serverCard(context, app, ssh, l, s));
        }
      }
    }
    return widgets;
  }

  Widget _serverCard(BuildContext context, AppState app, SshService ssh,
      AppLocalizations l, ServerProfile s) {
    final isActive = s.id == app.activeId;
    final isConnected =
        isActive && ssh.connectedServerId == s.id && ssh.isConnected;
    return Card(
      child: ListTile(
        leading: Icon(
          Icons.dns,
          color: isConnected
              ? const Color(0xFF4EC9B0)
              : (isActive ? Theme.of(context).colorScheme.primary : null),
        ),
        title: Text(s.name),
        subtitle: Text(
          '${s.displayTarget}\n${authLabel(l, s.auth)} · ${s.defaultDir}',
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          onSelected: (v) => _onMenu(context, app, ssh, s, v),
          itemBuilder: (_) => [
            if (!isActive)
              PopupMenuItem(value: 'activate', child: Text(l.makeActive)),
            if (isActive && !isConnected)
              PopupMenuItem(value: 'connect', child: Text(l.connect)),
            if (isConnected)
              PopupMenuItem(value: 'disconnect', child: Text(l.disconnect)),
            PopupMenuItem(value: 'edit', child: Text(l.edit)),
            PopupMenuItem(value: 'delete', child: Text(l.delete)),
          ],
        ),
        onTap: () => _onTapServer(context, app, ssh, s, isConnected),
      ),
    );
  }

  Future<void> _onMenu(BuildContext context, AppState app, SshService ssh,
      ServerProfile s, String v) async {
    switch (v) {
      case 'activate':
        await app.setActive(s.id);
        break;
      case 'connect':
        await app.setActive(s.id);
        await app.connectActive();
        if (ssh.error != null && context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(ssh.error!)));
        }
        break;
      case 'disconnect':
        await ssh.disconnect();
        break;
      case 'edit':
        if (context.mounted) await _edit(context, s);
        break;
      case 'delete':
        if (context.mounted) await _confirmDelete(context, app, s);
        break;
    }
  }

  Future<void> _onTapServer(BuildContext context, AppState app, SshService ssh,
      ServerProfile s, bool isConnected) async {
    if (isConnected) {
      app.goToTab(1); // вже підключений → Інфо
      return;
    }
    await app.setActive(s.id);
    await app.connectActive();
    if (ssh.error != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(ssh.error!)));
    }
  }

  Future<void> _edit(BuildContext context, ServerProfile? s) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ServerEditScreen(existing: s)),
    );
  }

  /// Free-ліміт вичерпано → запропонувати Pro.
  Future<void> _showUpgrade(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final go = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.workspace_premium, color: Colors.amber),
        title: Text(l.proLimitTitle),
        content: Text(l.proLimitBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.later)),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.upgradeToPro)),
        ],
      ),
    );
    if (go == true && context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SettingsScreen()),
      );
    }
  }

  Future<void> _confirmDelete(
      BuildContext context, AppState app, ServerProfile s) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l.deleteServerTitle),
        content: Text(l.deleteServerBody(s.name, s.displayTarget)),
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
    if (ok == true) await app.deleteServer(s.id);
  }
}

/// Пошукове поле над списком.
class _SearchField extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  const _SearchField({required this.hint, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: TextField(
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search),
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.dns_outlined, size: 64),
            const SizedBox(height: 12),
            Text(AppLocalizations.of(context).emptyServers,
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
