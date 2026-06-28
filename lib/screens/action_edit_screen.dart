import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../widgets.dart';

/// Додавання / редагування користувацької швидкої дії (скрипта).
class ActionEditScreen extends StatefulWidget {
  final QuickAction? existing;
  const ActionEditScreen({super.key, this.existing});

  @override
  State<ActionEditScreen> createState() => _ActionEditScreenState();
}

class _ActionEditScreenState extends State<ActionEditScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _command;
  late final TextEditingController _group;
  bool _dangerous = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _command = TextEditingController(text: e?.command ?? '');
    _group = TextEditingController(text: e?.group ?? '');
    _dangerous = e?.dangerous ?? false;
  }

  @override
  void dispose() {
    _title.dispose();
    _command.dispose();
    _group.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final app = context.read<AppState>();
    final e = widget.existing;
    final action = QuickAction(
      id: e?.id ?? QuickAction.create(title: '', command: '').id,
      title: _title.text.trim(),
      description: _command.text.trim(),
      command: _command.text.trim(),
      dangerous: _dangerous,
      group: _group.text.trim(),
    );
    if (e == null) {
      await app.addCustomAction(action);
    } else {
      await app.updateCustomAction(action);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final isNew = widget.existing == null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? l.newAction : l.editAction),
        actions: [
          IconButton(icon: const Icon(Icons.save), tooltip: l.save, onPressed: _save),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
            TextFormField(
              controller: _title,
              decoration: InputDecoration(
                labelText: l.fieldName,
                prefixIcon: const Icon(Icons.label),
                border: const OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? l.validatorRequired : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _command,
              maxLines: 4,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: InputDecoration(
                labelText: l.fieldCommand,
                hintText: 'df -h',
                prefixIcon: const Icon(Icons.terminal),
                border: const OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? l.validatorRequired : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _group,
              decoration: InputDecoration(
                labelText: l.fieldGroup,
                prefixIcon: const Icon(Icons.folder_outlined),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.fieldDangerous),
              value: _dangerous,
              onChanged: (v) => setState(() => _dangerous = v),
            ),
                ],
              ),
            ),
          ),
          SaveBar(label: l.save, onSave: _save),
        ],
      ),
    );
  }
}
