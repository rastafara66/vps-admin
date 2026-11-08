import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';

import '../app_state.dart';
import '../services/ssh_service.dart';
import '../shell_link.dart';
import '../terminal_keys.dart';
import '../theme.dart';
import '../widgets.dart';

/// Повноцінне інтерактивне вікно терміналу (SSH shell + xterm).
class TerminalTab extends StatelessWidget {
  const TerminalTab({super.key});

  @override
  Widget build(BuildContext context) {
    return RequireConnection(builder: (context) => const _TerminalView());
  }
}

class _TerminalView extends StatefulWidget {
  const _TerminalView();

  @override
  State<_TerminalView> createState() => _TerminalViewState();
}

class _TerminalViewState extends State<_TerminalView> {
  final Terminal _terminal = Terminal(maxLines: 10000);
  final TerminalController _controller = TerminalController();
  /// Відкритий shell. Після закриття каналу в нього нічого не йде —
  /// інакше OpenSSH рве все з'єднання (див. ShellLink).
  ShellLink? _link;
  StreamSubscription? _subOut;
  StreamSubscription? _subErr;
  bool _starting = true;
  String? _error;

  /// Shell завершився (exit, або програма з «команди при відкритті» вийшла).
  bool _ended = false;

  /// Екранна клавіша Ctrl натиснута: наступний символ піде як Ctrl+символ.
  bool _ctrlArmed = false;

  @override
  void initState() {
    super.initState();
    _terminal.onOutput = _onTerminalOutput;
    _terminal.onResize = (w, h, pw, ph) => _link?.resize(w, h);
    // Після першого кадру — інакше AppLocalizations.of(context) в _start
    // кидає виняток (dependOnInheritedWidget до завершення initState).
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (!mounted) return;
    final ssh = context.read<SshService>();
    final app = context.read<AppState>();
    final endedMsg = AppLocalizations.of(context).sessionEnded;
    try {
      // Розмір беремо з терміналу: при «Відкрити знову» вікно вже має свій
      // розмір, і нового onResize не буде.
      final session = await ssh.startShell(
        width: _terminal.viewWidth,
        height: _terminal.viewHeight,
      );
      final link = ShellLink.ssh(session);
      _link = link;

      _subOut = session.stdout.listen((data) {
        _terminal.write(utf8.decode(data, allowMalformed: true));
      });
      _subErr = session.stderr.listen((data) {
        _terminal.write(utf8.decode(data, allowMalformed: true));
      });

      // Стартова тека й «команда при відкритті терміналу» з профілю сервера
      // (напр. tmux new -A -s main — повернутися в постійну сесію).
      final server = app.activeServer;
      final startup = shellStartupInput(
        dir: server?.defaultDir,
        command: server?.startupCommand,
      );
      if (startup.isNotEmpty) _send(startup);

      void onEnded() {
        if (!mounted || !identical(_link, link)) return;
        _terminal.write('\r\n$endedMsg\r\n');
        setState(() {
          _ended = true;
          _ctrlArmed = false;
        });
      }

      unawaited(session.done.then((_) => onEnded(), onError: (_) => onEnded()));

      if (mounted) {
        setState(() {
          _starting = false;
          _ended = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _starting = false;
        });
      }
    }
  }

  /// Відкрити shell заново в тому самому вікні (історія екрана лишається).
  Future<void> _reopen() async {
    await _closeSession();
    _terminal.write('\r\n');
    setState(() {
      _starting = true;
      _error = null;
      _ended = false;
    });
    await _start();
  }

  Future<void> _closeSession() async {
    await _subOut?.cancel();
    await _subErr?.cancel();
    _subOut = null;
    _subErr = null;
    final link = _link;
    _link = null;
    link?.close();
  }

  /// Усе, що вводить користувач (клавіатура, вставка) і що відповідає
  /// сам термінал, іде сюди. Якщо екранна Ctrl натиснута — перетворюємо
  /// наступний символ на керуючий (Ctrl+b → 0x02 тощо).
  void _onTerminalOutput(String data) {
    if (_ctrlArmed && data.length == 1) {
      if (mounted) setState(() => _ctrlArmed = false);
      final c = ctrlChar(data);
      // Ctrl+j — це саме LF, його не перетворюємо.
      if (c != null) return _send(c);
    }
    _send(typedToTerminal(data));
  }

  void _send(String text) => _link?.send(text);

  /// Клавіша з панелі (стрілки, Tab, Esc) — з урахуванням режиму програми
  /// (vim/tmux перемикають стрілки на інші послідовності) і натиснутої Ctrl.
  void _key(TerminalKey key) {
    final ctrl = _ctrlArmed;
    if (ctrl) setState(() => _ctrlArmed = false);
    _terminal.keyInput(key, ctrl: ctrl);
  }

  /// «Очистити»: у tmux/vim/less (альтернативний екран) локальне стирання
  /// розсинхронізує картинку, тож просимо програму перемалюватись (Ctrl+L).
  void _clear() {
    if (_terminal.isUsingAltBuffer) {
      _send('\x0c');
    } else {
      _terminal.write('\x1b[2J\x1b[H');
    }
  }

  @override
  void dispose() {
    _subOut?.cancel();
    _subErr?.cancel();
    _link?.close();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (_starting) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text(l.shellOpenError(_error!), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _reopen,
                child: Text(l.tryAgain),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: TerminalView(
            _terminal,
            controller: _controller,
            // НЕ autofocus: інакше термінал у фоновій вкладці (IndexedStack)
            // хапає фокус одразу після підключення й вискакує клавіатура.
            autofocus: false,
            backgroundOpacity: 1,
            padding: const EdgeInsets.all(6),
          ),
        ),
        if (_ended)
          Material(
            color: context.appColors.panel,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(l.shellEnded)),
                  FilledButton.icon(
                    onPressed: _reopen,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(l.reopenShell),
                  ),
                ],
              ),
            ),
          ),
        _Toolbar(
          l: l,
          ctrlArmed: _ctrlArmed,
          onCtrl: () => setState(() => _ctrlArmed = !_ctrlArmed),
          onCtrlC: () => _send('\x03'),
          onKey: _key,
          onSend: _send,
          onClear: _clear,
          onPaste: () async {
            final data = await Clipboard.getData(Clipboard.kTextPlain);
            if (data?.text != null) _terminal.paste(data!.text!);
          },
        ),
      ],
    );
  }
}

/// Панель спецклавіш, яких немає на екранній клавіатурі.
class _Toolbar extends StatelessWidget {
  final AppLocalizations l;
  final bool ctrlArmed;
  final VoidCallback onCtrl;
  final VoidCallback onCtrlC;
  final void Function(TerminalKey key) onKey;
  final void Function(String text) onSend;
  final VoidCallback onClear;
  final VoidCallback onPaste;

  const _Toolbar({
    required this.l,
    required this.ctrlArmed,
    required this.onCtrl,
    required this.onCtrlC,
    required this.onKey,
    required this.onSend,
    required this.onClear,
    required this.onPaste,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.appColors.panel,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _btn(context, 'Ctrl', onCtrl,
                active: ctrlArmed, tooltip: l.keyCtrlHint),
            _btn(context, 'Ctrl-C', onCtrlC),
            _btn(context, 'Esc', () => onKey(TerminalKey.escape)),
            _btn(context, 'Tab', () => onKey(TerminalKey.tab)),
            // Enter без клавіатури: підтвердити вибір у меню програми,
            // не закриваючи пів екрана клавіатурою.
            _btn(context, '⏎ Enter', () => onKey(TerminalKey.enter)),
            _btn(context, '←', () => onKey(TerminalKey.arrowLeft)),
            _btn(context, '↑', () => onKey(TerminalKey.arrowUp)),
            _btn(context, '↓', () => onKey(TerminalKey.arrowDown)),
            _btn(context, '→', () => onKey(TerminalKey.arrowRight)),
            _sessionMenu(context),
            _btn(context, l.keyPaste, onPaste),
            _btn(context, l.keyClear, onClear),
          ],
        ),
      ),
    );
  }

  /// Меню «tmux»: типові команди з префіксом Ctrl+b, плюс від'єднання screen.
  Widget _sessionMenu(BuildContext context) {
    final items = <(String, String)>[
      (l.tmuxDetach, TmuxKey.detach.sequence),
      (l.tmuxNewWindow, TmuxKey.newWindow.sequence),
      (l.tmuxNextWindow, TmuxKey.nextWindow.sequence),
      (l.tmuxSessions, TmuxKey.chooseSession.sequence),
      (l.tmuxScroll, TmuxKey.scrollMode.sequence),
      (l.tmuxRedraw, TmuxKey.redraw.sequence),
      (l.screenDetach, screenDetachSequence),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: PopupMenuButton<String>(
        tooltip: l.tmuxMenuHint,
        onSelected: onSend,
        itemBuilder: (_) => [
          for (final (label, seq) in items)
            PopupMenuItem(value: seq, child: Text(label)),
        ],
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outline),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('tmux', style: TextStyle(fontSize: 12)),
              Icon(Icons.arrow_drop_up, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _btn(BuildContext context, String label, VoidCallback onTap,
      {bool active = false, String? tooltip}) {
    final scheme = Theme.of(context).colorScheme;
    final button = OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        minimumSize: const Size(0, 36),
        backgroundColor: active ? scheme.primary : null,
        foregroundColor: active ? scheme.onPrimary : null,
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: tooltip == null ? button : Tooltip(message: tooltip, child: button),
    );
  }
}
