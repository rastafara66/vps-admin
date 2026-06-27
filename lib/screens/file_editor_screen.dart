import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../theme.dart';

/// Простий, але надійний редактор текстового файлу (моноширинний).
/// Синтаксичну підсвітку можна додати пізніше (code_text_field/flutter_highlight).
class FileEditorScreen extends StatefulWidget {
  final String path;
  final String initialContent;
  final Future<void> Function(String content) onSave;

  const FileEditorScreen({
    super.key,
    required this.path,
    required this.initialContent,
    required this.onSave,
  });

  @override
  State<FileEditorScreen> createState() => _FileEditorScreenState();
}

class _FileEditorScreenState extends State<FileEditorScreen> {
  late final TextEditingController _ctrl;
  bool _dirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialContent);
    _ctrl.addListener(() {
      final d = _ctrl.text != widget.initialContent;
      if (d != _dirty) setState(() => _dirty = d);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String get _fileName => widget.path.split('/').last;

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    setState(() => _saving = true);
    try {
      await widget.onSave(_ctrl.text);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _dirty = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.saved)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.saveError('$e'))));
    }
  }

  Future<bool> _confirmExit() async {
    if (!_dirty) return true;
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l.unsavedTitle),
        content: Text(l.unsavedBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.stay)),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.exit)),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.appColors;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final lines = '\n'.allMatches(_ctrl.text).length + 1;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmExit()) nav.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_fileName, style: const TextStyle(fontSize: 15)),
              Text(widget.path,
                  style: TextStyle(fontSize: 11, color: muted),
                  overflow: TextOverflow.ellipsis),
            ],
          ),
          actions: [
            if (_saving)
              const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else
              IconButton(
                icon: Icon(Icons.save, color: _dirty ? Colors.amber : null),
                tooltip: l.save,
                onPressed: _dirty ? _save : null,
              ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                keyboardType: TextInputType.multiline,
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    height: 1.4,
                    color: c.codeText),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.all(12),
                  border: InputBorder.none,
                  filled: true,
                  fillColor: c.codeBg,
                ),
              ),
            ),
            Container(
              color: c.panel,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  Text(l.linesCount(lines),
                      style: TextStyle(fontSize: 11, color: muted)),
                  const Spacer(),
                  if (_dirty)
                    Text(l.modified,
                        style: const TextStyle(fontSize: 11, color: Colors.amber)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
