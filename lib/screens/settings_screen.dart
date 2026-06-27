import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../license.dart';

/// Налаштування додатка: ключ Claude, модель, біометричний замок.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _apiKey = TextEditingController();
  final _licenseKey = TextEditingController();
  bool _obscure = true;
  bool _loaded = false;
  bool _activating = false;

  /// Сторінка купівлі Pro (лендинг на сайті — реалізує бекенд-смуга).
  static const _buyUrl = 'https://yellow.in.ua/vps-admin';

  // Актуальні моделі Claude (станом на 2026).
  static const _models = [
    'claude-opus-4-8',
    'claude-sonnet-4-6',
    'claude-haiku-4-5-20251001',
    'claude-fable-5',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final key = await context.read<AppState>().claudeApiKey();
    if (!mounted) return;
    setState(() {
      _apiKey.text = key ?? '';
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _apiKey.dispose();
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
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _licenseSection(context, l),
                const Divider(height: 32),
                _SectionTitle(l.sectionAi),
                TextField(
                  controller: _apiKey,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'ANTHROPIC_API_KEY',
                    hintText: 'sk-ant-…',
                    prefixIcon: const Icon(Icons.key),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l.apiKeyNote,
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () async {
                    await app.setClaudeApiKey(_apiKey.text.trim());
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l.keySaved)));
                    }
                  },
                  icon: const Icon(Icons.save),
                  label: Text(l.saveKey),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value:
                      _models.contains(app.claudeModel) ? app.claudeModel : _models.first,
                  decoration: InputDecoration(
                    labelText: l.modelLabel,
                    prefixIcon: const Icon(Icons.smart_toy_outlined),
                  ),
                  items: [
                    for (final m in _models)
                      DropdownMenuItem(value: m, child: Text(m)),
                  ],
                  onChanged: (v) {
                    if (v != null) app.setClaudeModel(v);
                  },
                ),
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
                  title: Text(l.biometricLockTitle),
                  subtitle: Text(l.biometricLockSubtitle),
                  value: app.biometricLock,
                  onChanged: (v) => app.setBiometricLock(v),
                ),
                const Divider(height: 32),
                _SectionTitle(l.sectionAbout),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('VPS Admin'),
                  subtitle: Text(l.aboutSubtitle),
                ),
              ],
            ),
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
