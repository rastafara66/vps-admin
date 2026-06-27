import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';

import '../app_state.dart';
import '../services/ssh_service.dart';
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
  SSHSession? _session;
  StreamSubscription? _subOut;
  StreamSubscription? _subErr;
  bool _starting = true;
  String? _error;

  @override
  void initState() {
    super.initState();
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
      final session = await ssh.startShell(width: 80, height: 24);
      _session = session;

      _terminal.onOutput = (data) {
        session.write(Uint8List.fromList(utf8.encode(data)));
      };
      _terminal.onResize = (w, h, pw, ph) {
        session.resizeTerminal(w, h);
      };

      _subOut = session.stdout.listen((data) {
        _terminal.write(utf8.decode(data, allowMalformed: true));
      });
      _subErr = session.stderr.listen((data) {
        _terminal.write(utf8.decode(data, allowMalformed: true));
      });

      // Перейти у стартову теку сервера.
      final dir = app.activeServer?.defaultDir;
      if (dir != null && dir.isNotEmpty && dir != '/') {
        session.write(Uint8List.fromList(utf8.encode('cd "$dir"\n')));
      }

      unawaited(session.done.then((_) {
        if (mounted) {
          _terminal.write('\r\n$endedMsg\r\n');
        }
      }));

      if (mounted) setState(() => _starting = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _starting = false;
        });
      }
    }
  }

  void _sendCtrlC() {
    _session?.write(Uint8List.fromList([0x03]));
  }

  void _pasteAndRun(String text) {
    _session?.write(Uint8List.fromList(utf8.encode(text)));
  }

  @override
  void dispose() {
    _subOut?.cancel();
    _subErr?.cancel();
    try {
      _session?.close();
    } catch (_) {}
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
                onPressed: () {
                  setState(() {
                    _starting = true;
                    _error = null;
                  });
                  _start();
                },
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
            autofocus: true,
            backgroundOpacity: 1,
            padding: const EdgeInsets.all(6),
          ),
        ),
        _Toolbar(
          pasteLabel: l.keyPaste,
          clearLabel: l.keyClear,
          onCtrlC: _sendCtrlC,
          onTab: () => _pasteAndRun('\t'),
          onEsc: () => _pasteAndRun('\x1b'),
          onArrowUp: () => _pasteAndRun('\x1b[A'),
          onClear: () => _terminal.write('\x1b[2J\x1b[H'),
          onPaste: () async {
            final data = await Clipboard.getData(Clipboard.kTextPlain);
            if (data?.text != null) _pasteAndRun(data!.text!);
          },
        ),
      ],
    );
  }
}

/// Панель спецклавіш, яких немає на екранній клавіатурі.
class _Toolbar extends StatelessWidget {
  final String pasteLabel;
  final String clearLabel;
  final VoidCallback onCtrlC;
  final VoidCallback onTab;
  final VoidCallback onEsc;
  final VoidCallback onArrowUp;
  final VoidCallback onClear;
  final VoidCallback onPaste;

  const _Toolbar({
    required this.pasteLabel,
    required this.clearLabel,
    required this.onCtrlC,
    required this.onTab,
    required this.onEsc,
    required this.onArrowUp,
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
            _btn('Ctrl-C', onCtrlC),
            _btn('Tab', onTab),
            _btn('Esc', onEsc),
            _btn('↑', onArrowUp),
            _btn(pasteLabel, onPaste),
            _btn(clearLabel, onClear),
          ],
        ),
      ),
    );
  }

  Widget _btn(String label, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: const Size(0, 36),
          ),
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
      );
}
