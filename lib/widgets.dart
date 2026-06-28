import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'models.dart';
import 'services/ssh_service.dart';
import 'theme.dart';

/// Локалізований підпис способу автентифікації.
String authLabel(AppLocalizations l, AuthType auth) =>
    auth == AuthType.password ? l.authPassword : l.authKey;

/// Заголовок теки (групи): тап згортає/розгортає вміст.
class GroupHeader extends StatelessWidget {
  final String text;
  final int count;
  final bool collapsed;
  final VoidCallback onTap;
  const GroupHeader({
    super.key,
    required this.text,
    required this.count,
    required this.collapsed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Row(
          children: [
            Icon(collapsed ? Icons.chevron_right : Icons.expand_more,
                size: 20, color: c),
            const SizedBox(width: 4),
            Icon(Icons.folder_outlined, size: 16, color: c),
            const SizedBox(width: 6),
            Expanded(
              child: Text(text.toUpperCase(),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: c)),
            ),
            Text('$count',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

/// Закріплена внизу панель із кнопкою «Зберегти» — завжди видима
/// (на будь-якій орієнтації), піднімається над клавіатурою.
class SaveBar extends StatelessWidget {
  final String label;
  final VoidCallback onSave;
  const SaveBar({super.key, required this.label, required this.onSave});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onSave,
              icon: const Icon(Icons.save),
              label: Text(label),
            ),
          ),
        ),
      ),
    );
  }
}

/// Обгортка, що вимагає активного SSH-з'єднання.
/// Якщо не підключені — показує заглушку з кнопкою «Підключитися».
class RequireConnection extends StatelessWidget {
  final Widget Function(BuildContext context) builder;
  const RequireConnection({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final ssh = context.watch<SshService>();
    final l = AppLocalizations.of(context);

    if (app.activeServer == null) {
      return _Notice(
        icon: Icons.dns_outlined,
        text: l.noActiveServer,
      );
    }
    if (ssh.isConnected && ssh.connectedServerId == app.activeId) {
      return builder(context);
    }

    final connecting = ssh.status == SshStatus.connecting;
    return _Notice(
      icon: Icons.link_off,
      text: ssh.error ?? l.noConnectionTo(app.activeServer!.name),
      action: connecting
          ? const CircularProgressIndicator()
          : FilledButton.icon(
              onPressed: () async {
                await app.connectActive();
                if (ssh.error != null && context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(ssh.error!)));
                }
              },
              icon: const Icon(Icons.link),
              label: Text(l.connectToServer(app.activeServer!.name)),
            ),
    );
  }
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;
  const _Notice({required this.icon, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

/// Моноширинний блок виводу команди.
class MonoOutput extends StatelessWidget {
  final String text;
  final bool selectable;
  const MonoOutput(this.text, {super.key, this.selectable = true});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final style = TextStyle(
      fontFamily: 'monospace',
      fontSize: 12.5,
      height: 1.35,
      color: c.codeText,
    );
    final child = selectable
        ? SelectableText(text, style: style)
        : Text(text, style: style);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.codeBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.codeBorder),
      ),
      child: child,
    );
  }
}
