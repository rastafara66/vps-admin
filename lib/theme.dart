import 'package:flutter/material.dart';

/// Додаткові семантичні кольори (поверхні «коду», статуси), що залежать від теми.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color panel; // картки, тулбари, поверхні
  final Color codeBg; // фон моноширинного виводу / редактора
  final Color codeBorder;
  final Color codeText;
  final Color online; // індикатор підключення
  final Color folder; // іконка теки
  final Color bubbleUser; // бульбашка користувача в AI-чаті
  final Color bubbleAssistant;

  const AppColors({
    required this.panel,
    required this.codeBg,
    required this.codeBorder,
    required this.codeText,
    required this.online,
    required this.folder,
    required this.bubbleUser,
    required this.bubbleAssistant,
  });

  static const dark = AppColors(
    panel: Color(0xFF252526),
    codeBg: Color(0xFF1A1A1A),
    codeBorder: Color(0xFF333333),
    codeText: Color(0xFFD4D4D4),
    online: Color(0xFF4EC9B0),
    folder: Color(0xFFE2C08D),
    bubbleUser: Color(0xFF264F78),
    bubbleAssistant: Color(0xFF2D2D30),
  );

  static const light = AppColors(
    panel: Color(0xFFFFFFFF),
    codeBg: Color(0xFFF3F3F3),
    codeBorder: Color(0xFFD4D4D4),
    codeText: Color(0xFF1E1E1E),
    online: Color(0xFF137A62),
    folder: Color(0xFFB8860B),
    bubbleUser: Color(0xFFCCE3FF),
    bubbleAssistant: Color(0xFFEDEDED),
  );

  @override
  AppColors copyWith({
    Color? panel,
    Color? codeBg,
    Color? codeBorder,
    Color? codeText,
    Color? online,
    Color? folder,
    Color? bubbleUser,
    Color? bubbleAssistant,
  }) =>
      AppColors(
        panel: panel ?? this.panel,
        codeBg: codeBg ?? this.codeBg,
        codeBorder: codeBorder ?? this.codeBorder,
        codeText: codeText ?? this.codeText,
        online: online ?? this.online,
        folder: folder ?? this.folder,
        bubbleUser: bubbleUser ?? this.bubbleUser,
        bubbleAssistant: bubbleAssistant ?? this.bubbleAssistant,
      );

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      panel: Color.lerp(panel, other.panel, t)!,
      codeBg: Color.lerp(codeBg, other.codeBg, t)!,
      codeBorder: Color.lerp(codeBorder, other.codeBorder, t)!,
      codeText: Color.lerp(codeText, other.codeText, t)!,
      online: Color.lerp(online, other.online, t)!,
      folder: Color.lerp(folder, other.folder, t)!,
      bubbleUser: Color.lerp(bubbleUser, other.bubbleUser, t)!,
      bubbleAssistant: Color.lerp(bubbleAssistant, other.bubbleAssistant, t)!,
    );
  }
}

/// Зручний доступ: context.appColors
extension AppColorsX on BuildContext {
  AppColors get appColors => Theme.of(this).extension<AppColors>()!;
}

/// Тема в дусі VS Code: темна + світла.
class AppTheme {
  static const seed = Color(0xFF2C8FFF);
  static const mono = 'monospace';

  static ThemeData dark() => _build(Brightness.dark, AppColors.dark);
  static ThemeData light() => _build(Brightness.light, AppColors.light);

  static ThemeData _build(Brightness b, AppColors c) {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: b);
    final scaffoldBg = b == Brightness.dark
        ? const Color(0xFF1E1E1E)
        : const Color(0xFFF5F5F5);
    final base = ThemeData(useMaterial3: true, brightness: b, colorScheme: scheme);
    return base.copyWith(
      scaffoldBackgroundColor: scaffoldBg,
      extensions: [c],
      appBarTheme: AppBarTheme(
        backgroundColor: c.panel,
        foregroundColor: scheme.onSurface,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.panel,
        indicatorColor: seed.withValues(alpha: 0.25),
        labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 11)),
      ),
      cardTheme: CardTheme(
        color: c.panel,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}

/// Колір статусу підключення (працює на обох темах).
Color statusColor(bool connected, bool connecting) {
  if (connecting) return Colors.amber;
  return connected ? const Color(0xFF4EC9B0) : Colors.grey;
}
