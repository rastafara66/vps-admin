import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// Вбудована довідка: по одному розділу на кожну частину додатка.
/// Тексти беруться з локалізації (EN/UK), команди можна виділяти/копіювати.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    final sections = <_HelpSection>[
      _HelpSection(Icons.dns_outlined, l.helpServersTitle, l.helpServersBody),
      _HelpSection(Icons.vpn_key_outlined, l.helpSshTitle, l.helpSshBody),
      _HelpSection(Icons.monitor_heart_outlined, l.helpInfoTitle, l.helpInfoBody),
      _HelpSection(Icons.terminal, l.helpTerminalTitle, l.helpTerminalBody),
      _HelpSection(Icons.folder_outlined, l.helpFilesTitle, l.helpFilesBody),
      _HelpSection(Icons.smart_toy_outlined, l.helpAiTitle, l.helpAiBody),
      _HelpSection(Icons.bolt_outlined, l.helpActionsTitle, l.helpActionsBody),
      _HelpSection(Icons.shield_outlined, l.helpSecurityTitle, l.helpSecurityBody),
      _HelpSection(Icons.system_update, l.helpUpdatesTitle, l.helpUpdatesBody),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(l.helpTitle)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Text(l.helpIntro,
                style: TextStyle(fontSize: 13, color: muted)),
          ),
          for (final s in sections) _HelpTile(section: s),
        ],
      ),
    );
  }
}

class _HelpSection {
  final IconData icon;
  final String title;
  final String body;
  const _HelpSection(this.icon, this.title, this.body);
}

class _HelpTile extends StatelessWidget {
  final _HelpSection section;
  const _HelpTile({required this.section});

  /// SSH-ключі — найчастіше потрібний розділ, тож розгорнутий за замовчуванням.
  bool get _initiallyOpen => section.title.contains('SSH');

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: Icon(section.icon),
      title: Text(section.title,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      initiallyExpanded: _initiallyOpen,
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText(
          section.body,
          style: const TextStyle(fontSize: 14, height: 1.45),
        ),
      ],
    );
  }
}
