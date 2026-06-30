import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../license.dart';
import '../services/ai_service.dart';
import '../services/update_service.dart';
import 'help_screen.dart';
import 'update_dialog.dart';

/// Налаштування додатка: AI-провайдер, тема, мова, безпека, (ліцензія).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _licenseKey = TextEditingController();
  bool _activating = false;

  /// Сторінка купівлі Pro (лендинг на сайті — реалізує бекенд-смуга).
  static const _buyUrl = 'https://yellow.in.ua/vps-admin';

  /// Донат — банка monobank (грн; приймає й іноземні картки).
  static const _jarUrl = 'https://send.monobank.ua/jar/DGAVuFpJW';
  static const _jarCard = '4874 1000 3055 6727';

  @override
  void dispose() {
    _licenseKey.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    final l = AppLocalizations.of(context);
    final license = context.read<LicenseService>();
    setState(() => _activating = true);
    final res = await license.activate(_licenseKey.text);
    if (!mounted) return;
    setState(() => _activating = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(res.ok ? l.activationOk : l.activationFailed(res.error ?? '')),
    ));
    if (res.ok) _licenseKey.clear();
  }

  Future<void> _openBuy() async {
    final uri = Uri.parse(_buyUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_buyUrl)));
      }
    }
  }

  Future<void> _donate() async {
    final uri = Uri.parse(_jarUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text(_jarUrl)));
      }
    }
  }

  void _copyCard() {
    Clipboard.setData(const ClipboardData(text: _jarCard));
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).cardCopied)));
  }

  Widget _supportSection(AppLocalizations l) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(l.sectionSupport),
        Text(l.supportNote, style: TextStyle(fontSize: 12, color: muted)),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _donate,
          icon: const Icon(Icons.favorite),
          label: Text(l.donateMonobank),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(Icons.credit_card, size: 18, color: muted),
            const SizedBox(width: 8),
            const SelectableText(_jarCard,
                style: TextStyle(fontFamily: 'monospace', fontSize: 13)),
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              tooltip: l.copy,
              onPressed: _copyCard,
            ),
          ],
        ),
      ],
    );
  }

  bool _checking = false;

  Future<void> _checkUpdates() async {
    final l = AppLocalizations.of(context);
    setState(() => _checking = true);
    final info = await UpdateService.check();
    if (!mounted) return;
    setState(() => _checking = false);
    if (info != null) {
      await showUpdateDialog(context, info);
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.upToDate)));
    }
  }

  Widget _updatesSection(AppLocalizations l, AppState app) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(l.sectionUpdates),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'off', label: Text(l.updateOff)),
            ButtonSegment(value: 'notify', label: Text(l.updateNotify)),
            ButtonSegment(value: 'auto', label: Text(l.updateAuto)),
          ],
          selected: {app.updateMode},
          showSelectedIcon: false,
          onSelectionChanged: (s) => app.setUpdateMode(s.first),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _checking ? null : _checkUpdates,
              icon: _checking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.system_update),
              label: Text(l.checkUpdates),
            ),
            const SizedBox(width: 12),
            FutureBuilder<String>(
              future: UpdateService.currentVersion(),
              builder: (_, snap) => Text(
                snap.hasData ? l.currentVersion(snap.data!) : '',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _licenseSection(BuildContext context, AppLocalizations l) {
    final license = context.watch<LicenseService>();
    final isPro = license.isPro;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(l.sectionLicense),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(isPro ? Icons.workspace_premium : Icons.lock_open,
              color: isPro ? Colors.amber : null),
          title: Text(isPro ? l.proActive : l.tierFree),
          subtitle: Text(license.entitlement.email ??
              (isPro ? '' : l.proLimitBody.split('\n').first)),
        ),
        if (isPro)
          OutlinedButton.icon(
            onPressed: () => license.deactivate(),
            icon: const Icon(Icons.logout),
            label: Text(l.removeLicense),
          )
        else if (license.supportsActivation) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _licenseKey,
            decoration: InputDecoration(
              labelText: l.licenseKeyLabel,
              prefixIcon: const Icon(Icons.vpn_key),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _activating ? null : _activate,
                  icon: _activating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check),
                  label: Text(l.activate),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openBuy,
                  icon: const Icon(Icons.shopping_cart_outlined),
                  label: Text(l.buyPro),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (kMonetizationEnabled) ...[
            _licenseSection(context, l),
            const Divider(height: 32),
          ],
          const _AiSettings(),
          const Divider(height: 32),
          _updatesSection(l, app),
          const Divider(height: 32),
          _SectionTitle(l.sectionTheme),
          SegmentedButton<ThemeMode>(
            segments: [
              ButtonSegment(
                  value: ThemeMode.system,
                  icon: const Icon(Icons.brightness_auto),
                  label: Text(l.themeSystem)),
              ButtonSegment(
                  value: ThemeMode.light,
                  icon: const Icon(Icons.light_mode),
                  label: Text(l.themeLight)),
              ButtonSegment(
                  value: ThemeMode.dark,
                  icon: const Icon(Icons.dark_mode),
                  label: Text(l.themeDark)),
            ],
            selected: {app.themeMode},
            showSelectedIcon: false,
            onSelectionChanged: (s) => app.setThemeMode(s.first),
          ),
          const Divider(height: 32),
          _SectionTitle(l.sectionLanguage),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: '', label: Text(l.languageSystem)),
              const ButtonSegment(value: 'en', label: Text('English')),
              const ButtonSegment(value: 'uk', label: Text('Українська')),
            ],
            selected: {app.localeCode},
            showSelectedIcon: false,
            onSelectionChanged: (s) => app.setLocaleCode(s.first),
          ),
          const Divider(height: 32),
          _SectionTitle(l.sectionSecurity),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.biometricLockTitle),
            subtitle: Text(l.biometricLockSubtitle),
            value: app.biometricLock,
            onChanged: (v) => app.setBiometricLock(v),
          ),
          const Divider(height: 32),
          _SectionTitle(l.sectionAbout),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.info_outline),
            title: const Text('VPS Admin'),
            subtitle: Text(l.aboutSubtitle),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.help_outline),
            title: Text(l.helpTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HelpScreen()),
            ),
          ),
          const Divider(height: 32),
          _supportSection(l),
        ],
      ),
    );
  }
}

/// Налаштування AI-провайдера (Claude / OpenAI / Gemini / OpenAI-сумісний).
class _AiSettings extends StatefulWidget {
  const _AiSettings();

  @override
  State<_AiSettings> createState() => _AiSettingsState();
}

class _AiSettingsState extends State<_AiSettings> {
  late AiProvider _provider;
  final _key = TextEditingController();
  final _model = TextEditingController();
  final _baseUrl = TextEditingController();
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _provider = app.aiProvider;
    _baseUrl.text = app.aiBaseUrl;
    _loadFor(_provider);
  }

  Future<void> _loadFor(AiProvider p) async {
    final app = context.read<AppState>();
    final key = await app.aiKey(p);
    if (!mounted) return;
    setState(() {
      _key.text = key ?? '';
      _model.text = app.aiModel(p);
    });
  }

  Future<void> _onProvider(AiProvider p) async {
    await context.read<AppState>().setAiProvider(p);
    setState(() => _provider = p);
    await _loadFor(p);
  }

  Future<void> _save() async {
    final app = context.read<AppState>();
    final l = AppLocalizations.of(context);
    await app.setAiKey(_provider, _key.text.trim());
    await app.setAiModel(_provider, _model.text.trim());
    if (_provider.needsBaseUrl) await app.setAiBaseUrl(_baseUrl.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.keySaved)));
    }
  }

  @override
  void dispose() {
    _key.dispose();
    _model.dispose();
    _baseUrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(l.sectionAi),
        DropdownButtonFormField<AiProvider>(
          value: _provider,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: l.aiProviderLabel,
            prefixIcon: const Icon(Icons.smart_toy_outlined),
          ),
          items: [
            for (final p in AiProvider.values)
              DropdownMenuItem(value: p, child: Text(p.label)),
          ],
          onChanged: (p) {
            if (p != null) _onProvider(p);
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _key,
          obscureText: _obscure,
          decoration: InputDecoration(
            labelText: 'API key',
            hintText: _provider.keyHint,
            prefixIcon: const Icon(Icons.key),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _model,
          decoration: InputDecoration(
            labelText: l.modelLabel,
            hintText: _provider.defaultModel,
            prefixIcon: const Icon(Icons.tune),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final m in _provider.suggestedModels)
              ActionChip(
                label: Text(m, style: const TextStyle(fontSize: 12)),
                onPressed: () {
                  setState(() => _model.text = m);
                  context.read<AppState>().setAiModel(_provider, m);
                },
              ),
          ],
        ),
        if (_provider.needsBaseUrl) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _baseUrl,
            decoration: InputDecoration(
              labelText: l.aiBaseUrlLabel,
              hintText: 'https://host:11434/v1',
              prefixIcon: const Icon(Icons.link),
            ),
          ),
        ],
        const SizedBox(height: 6),
        Text(l.apiKeyNote, style: TextStyle(fontSize: 12, color: muted)),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save),
          label: Text(l.saveKey),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary)),
    );
  }
}
