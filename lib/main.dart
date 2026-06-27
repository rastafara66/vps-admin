import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'license.dart';
import 'screens/home_screen.dart';
import 'services/ssh_service.dart';
import 'services/store.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await Store.open();
  final ssh = SshService();
  // Open-core (free): 1 сервер, без активації Pro.
  // Офіційна збірка підставляє приватний ProLicenseService.
  final LicenseService license = FreeLicenseService();
  await license.init();
  final appState = AppState(store, ssh, license);
  await appState.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appState),
        ChangeNotifierProvider.value(value: ssh),
        ChangeNotifierProvider<LicenseService>.value(value: license),
      ],
      child: const VpsAdminApp(),
    ),
  );
}

class VpsAdminApp extends StatelessWidget {
  const VpsAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final code = app.localeCode;
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: app.themeMode,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // '' → за локаллю пристрою; інакше примусова мова з налаштувань.
      locale: code.isEmpty ? null : Locale(code),
      home: const _Gate(),
    );
  }
}

/// Замок на вхід: якщо ввімкнено біометрію — вимагаємо автентифікацію.
class _Gate extends StatefulWidget {
  const _Gate();

  @override
  State<_Gate> createState() => _GateState();
}

class _GateState extends State<_Gate> {
  bool _unlocked = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    // Після першого кадру — щоб локалізація вже була доступна через context.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAuth());
  }

  Future<void> _maybeAuth() async {
    if (!mounted) return;
    final app = context.read<AppState>();
    if (!app.biometricLock) {
      setState(() {
        _unlocked = true;
        _checking = false;
      });
      return;
    }
    final reason = AppLocalizations.of(context).lockReason;
    setState(() => _checking = true);
    try {
      final auth = LocalAuthentication();
      final can = await auth.isDeviceSupported();
      if (!can) {
        _unlocked = true;
      } else {
        _unlocked = await auth.authenticate(
          localizedReason: reason,
          options: const AuthenticationOptions(stickyAuth: true),
        );
      }
    } catch (_) {
      _unlocked = true; // не блокуємо доступ через помилку біометрії
    }
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked) return const HomeScreen();
    final l = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 64),
            const SizedBox(height: 16),
            Text(l.lockTitle),
            const SizedBox(height: 16),
            if (_checking)
              const CircularProgressIndicator()
            else
              FilledButton.icon(
                onPressed: _maybeAuth,
                icon: const Icon(Icons.fingerprint),
                label: Text(l.unlock),
              ),
          ],
        ),
      ),
    );
  }
}
