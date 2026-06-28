import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../widgets.dart';

/// Форма додавання / редагування VPS-сервера + секрет.
class ServerEditScreen extends StatefulWidget {
  final ServerProfile? existing;
  const ServerEditScreen({super.key, this.existing});

  @override
  State<ServerEditScreen> createState() => _ServerEditScreenState();
}

class _ServerEditScreenState extends State<ServerEditScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _user;
  late final TextEditingController _dir;
  late final TextEditingController _group;
  final _password = TextEditingController();
  final _key = TextEditingController();
  final _passphrase = TextEditingController();

  AuthType _auth = AuthType.key;
  bool _loadingSecret = false;
  bool _secretLoaded = false;
  bool _obscurePw = true;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _host = TextEditingController(text: e?.host ?? '');
    _port = TextEditingController(text: '${e?.port ?? 22}');
    _user = TextEditingController(text: e?.username ?? 'ubuntu');
    _dir = TextEditingController(text: e?.defaultDir ?? '/home/ubuntu');
    _group = TextEditingController(text: e?.group ?? '');
    _auth = e?.auth ?? AuthType.key;
    if (e != null) _loadSecret(e.id);
  }

  Future<void> _loadSecret(String id) async {
    setState(() => _loadingSecret = true);
    final secret = await context.read<AppState>().secretFor(id);
    if (!mounted) return;
    setState(() {
      _password.text = secret?.password ?? '';
      _key.text = secret?.privateKeyPem ?? '';
      _passphrase.text = secret?.passphrase ?? '';
      _loadingSecret = false;
      _secretLoaded = true;
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _host, _port, _user, _dir, _group, _password, _key, _passphrase]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? l.newServer : l.editServer),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: l.save,
            onPressed: _save,
          ),
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
            _field(_name, l.fieldName, hint: l.fieldNameHint, icon: Icons.label),
            _field(_host, l.fieldHost, icon: Icons.lan, validator: (v) => _required(l, v)),
            Row(
              children: [
                Expanded(
                  child: _field(_port, l.fieldPort,
                      icon: Icons.numbers,
                      keyboard: TextInputType.number,
                      validator: (v) =>
                          int.tryParse(v ?? '') == null ? l.validatorNumber : null),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: _field(_user, l.fieldUser,
                      icon: Icons.person, validator: (v) => _required(l, v)),
                ),
              ],
            ),
            _field(_dir, l.fieldStartDir, icon: Icons.folder_open),
            _field(_group, l.fieldGroup, icon: Icons.folder_outlined),
            const SizedBox(height: 8),
            SegmentedButton<AuthType>(
              segments: [
                ButtonSegment(value: AuthType.key, label: Text(l.authKey)),
                ButtonSegment(value: AuthType.password, label: Text(l.authPassword)),
              ],
              selected: {_auth},
              onSelectionChanged: (s) => setState(() => _auth = s.first),
            ),
            const SizedBox(height: 12),
            if (_loadingSecret)
              const Padding(
                padding: EdgeInsets.all(8),
                child: LinearProgressIndicator(),
              )
            else if (_auth == AuthType.password)
              _field(_password, l.fieldPassword,
                  icon: Icons.password,
                  obscure: _obscurePw,
                  suffix: IconButton(
                    icon: Icon(_obscurePw ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscurePw = !_obscurePw),
                  ))
            else ...[
              _field(_key, l.fieldPrivateKey,
                  icon: Icons.key,
                  hint: '-----BEGIN OPENSSH PRIVATE KEY-----',
                  maxLines: 6,
                  mono: true),
              _field(_passphrase, l.fieldPassphrase,
                  icon: Icons.lock, obscure: true),
            ],
            const SizedBox(height: 8),
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.shield_outlined, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(l.secretNote,
                          style: const TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
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

  String? _required(AppLocalizations l, String? v) =>
      (v == null || v.trim().isEmpty) ? l.validatorRequired : null;

  Widget _field(
    TextEditingController c,
    String label, {
    String? hint,
    IconData? icon,
    TextInputType? keyboard,
    String? Function(String?)? validator,
    bool obscure = false,
    int maxLines = 1,
    bool mono = false,
    Widget? suffix,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextFormField(
        controller: c,
        obscureText: obscure,
        keyboardType: keyboard,
        maxLines: obscure ? 1 : maxLines,
        validator: validator,
        style: mono ? const TextStyle(fontFamily: 'monospace', fontSize: 12) : null,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: icon == null ? null : Icon(icon),
          suffixIcon: suffix,
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final app = context.read<AppState>();
    final existing = widget.existing;
    final profile = ServerProfile(
      id: existing?.id,
      name: _name.text.trim().isEmpty ? _host.text.trim() : _name.text.trim(),
      host: _host.text.trim(),
      port: int.tryParse(_port.text.trim()) ?? 22,
      username: _user.text.trim(),
      auth: _auth,
      defaultDir: _dir.text.trim().isEmpty ? '/' : _dir.text.trim(),
      group: _group.text.trim(),
    );

    ServerSecret? secret;
    // Для нового сервера або якщо ми завантажили/змінили секрет — зберігаємо.
    if (existing == null || _secretLoaded) {
      secret = ServerSecret(
        password: _auth == AuthType.password ? _password.text : null,
        privateKeyPem: _auth == AuthType.key ? _key.text : null,
        passphrase:
            _auth == AuthType.key && _passphrase.text.isNotEmpty ? _passphrase.text : null,
      );
    }

    await app.upsertServer(profile, secret: secret);
    if (mounted) Navigator.of(context).pop();
  }
}
