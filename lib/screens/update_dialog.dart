import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../services/update_service.dart';

/// Показати діалог оновлення. autoStart=true — одразу почати завантаження.
Future<void> showUpdateDialog(BuildContext context, UpdateInfo info,
    {bool autoStart = false}) {
  return showDialog(
    context: context,
    builder: (_) => _UpdateDialog(info: info, autoStart: autoStart),
  );
}

class _UpdateDialog extends StatefulWidget {
  final UpdateInfo info;
  final bool autoStart;
  const _UpdateDialog({required this.info, required this.autoStart});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double? _progress;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _start());
    }
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _progress = null;
    });
    try {
      await UpdateService.downloadAndInstall(
        widget.info,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final notes = widget.info.notes;
    return AlertDialog(
      icon: const Icon(Icons.system_update),
      title: Text(l.updateAvailable(widget.info.version)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (notes.isNotEmpty)
              Text(notes.length > 600 ? '${notes.substring(0, 600)}…' : notes,
                  style: const TextStyle(fontSize: 13)),
            if (_busy) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 8),
              Text(
                _progress == null
                    ? l.downloading
                    : '${l.downloading} ${(_progress! * 100).toStringAsFixed(0)}%',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l.later),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _start,
          icon: const Icon(Icons.download),
          label: Text(l.updateNow),
        ),
      ],
    );
  }
}
