import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../services/claude_service.dart';
import '../services/ssh_service.dart';
import '../theme.dart';
import 'settings_screen.dart';

/// Чат із Claude. AI може пропонувати команди у ```bash блоках;
/// під кожним блоком — кнопка «Виконати» (по SSH, із підтвердженням).
class AiTab extends StatefulWidget {
  const AiTab({super.key});

  @override
  State<AiTab> createState() => _AiTabState();
}

class _AiTabState extends State<AiTab> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _sending = false;
  bool _hasKey = false;

  @override
  void initState() {
    super.initState();
    _checkKey();
  }

  Future<void> _checkKey() async {
    final key = await context.read<AppState>().claudeApiKey();
    if (mounted) setState(() => _hasKey = key != null && key.trim().isNotEmpty);
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    final app = context.read<AppState>();
    final client = await app.claudeClient();
    if (client == null) {
      if (mounted) _snack(AppLocalizations.of(context).setApiKeyFirst);
      return;
    }
    setState(() {
      _messages.add(ChatMessage('user', text));
      _input.clear();
      _sending = true;
    });
    _scrollDown();
    try {
      final reply = await client.send(_messages);
      setState(() => _messages.add(ChatMessage('assistant', reply)));
    } catch (e) {
      setState(() => _messages.add(ChatMessage('assistant', '⚠️ $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollDown();
    }
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  /// Виконати запропоновану команду по SSH (з підтвердженням) і повернути результат у чат.
  Future<void> _runCommand(String command) async {
    final l = AppLocalizations.of(context);
    final ssh = context.read<SshService>();
    if (!ssh.isConnected) {
      _snack(l.noSshConnection);
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l.runCommandTitle),
        content: SelectableText(command,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
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
    if (confirm != true) return;

    final result = await ssh.exec(command);
    final out = result.combined.trim();
    final block =
        '\$ $command\n${out.isEmpty ? l.noOutput : out}\n[exit ${result.exitCode}]';
    // Додаємо результат як повідомлення користувача — щоб AI бачив реальний вивід.
    setState(() {
      _messages.add(ChatMessage('user', '${l.execResult}\n```\n$block\n```'));
    });
    _scrollDown();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (!_hasKey) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.smart_toy_outlined, size: 56,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(l.aiNeedKey, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const SettingsScreen()));
                  _checkKey();
                },
                icon: const Icon(Icons.key),
                label: Text(l.aiSettingsBtn),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: _messages.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      l.aiEmptyHint,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(8),
                  itemCount: _messages.length,
                  itemBuilder: (context, i) =>
                      _MessageBubble(_messages[i], onRun: _runCommand),
                ),
        ),
        if (_sending) const LinearProgressIndicator(),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: l.messageHint,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _sending ? null : _send,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final Future<void> Function(String command) onRun;
  const _MessageBubble(this.message, {required this.onRun});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final commands = isUser ? const <String>[] : extractCommands(message.text);
    final c = context.appColors;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.85),
        decoration: BoxDecoration(
          color: isUser ? c.bubbleUser : c.bubbleAssistant,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(message.text,
                style: const TextStyle(fontSize: 13.5, height: 1.4)),
            for (final cmd in commands)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _CommandChip(cmd, onRun: onRun),
              ),
          ],
        ),
      ),
    );
  }
}

class _CommandChip extends StatelessWidget {
  final String command;
  final Future<void> Function(String command) onRun;
  const _CommandChip(this.command, {required this.onRun});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.appColors;
    return Container(
      decoration: BoxDecoration(
        color: c.codeBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.codeBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: SelectableText(command,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () => Clipboard.setData(ClipboardData(text: command)),
                icon: const Icon(Icons.copy, size: 16),
                label: Text(l.copy),
              ),
              TextButton.icon(
                onPressed: () => onRun(command),
                icon: const Icon(Icons.play_arrow, size: 18),
                label: Text(l.run),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
