import 'package:flutter/material.dart';

/// Colours for money and payment states, in light and dark.
@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({
    required this.owe,
    required this.oweContainer,
    required this.owed,
    required this.owedContainer,
    required this.pending,
    required this.pendingContainer,
  });

  /// Money you owe, unpaid and overdue.
  final Color owe;
  final Color oweContainer;

  /// Money owed to you, and paid.
  final Color owed;
  final Color owedContainer;

  /// Marked paid, waiting for confirmation.
  final Color pending;
  final Color pendingContainer;

  static const light = StatusColors(
    owe: Color(0xFFB3261E),
    oweContainer: Color(0xFFFCE8E6),
    owed: Color(0xFF0B6E4F),
    owedContainer: Color(0xFFDDF3E8),
    pending: Color(0xFF8A5300),
    pendingContainer: Color(0xFFFFEFD2),
  );

  static const dark = StatusColors(
    owe: Color(0xFFFFB4AB),
    oweContainer: Color(0xFF4A1512),
    owed: Color(0xFF7FDDB3),
    owedContainer: Color(0xFF0E3B2B),
    pending: Color(0xFFFFCB7A),
    pendingContainer: Color(0xFF4A3305),
  );

  static StatusColors of(BuildContext context) => Theme.of(context).extension<StatusColors>() ?? light;

  @override
  StatusColors copyWith() => this;

  @override
  StatusColors lerp(ThemeExtension<StatusColors>? other, double t) {
    if (other is! StatusColors) return this;
    return StatusColors(
      owe: Color.lerp(owe, other.owe, t)!,
      oweContainer: Color.lerp(oweContainer, other.oweContainer, t)!,
      owed: Color.lerp(owed, other.owed, t)!,
      owedContainer: Color.lerp(owedContainer, other.owedContainer, t)!,
      pending: Color.lerp(pending, other.pending, t)!,
      pendingContainer: Color.lerp(pendingContainer, other.pendingContainer, t)!,
    );
  }
}

/// Gradients for hero cards and highlights.
class Brand {
  Brand._();

  static const fontFamily = 'PlusJakartaSans';

  static LinearGradient hero(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: dark
          ? const [Color(0xFF0E4D3A), Color(0xFF0F6B57), Color(0xFF16807A)]
          : const [Color(0xFF0B6E4F), Color(0xFF12936B), Color(0xFF1FA597)],
    );
  }

  static const onHero = Colors.white;
  static Color onHeroMuted = Colors.white.withValues(alpha: 0.78);

  /// Soft coloured shadow under hero cards.
  static List<BoxShadow> glow(BuildContext context) => [
    BoxShadow(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.28),
      blurRadius: 28,
      offset: const Offset(0, 12),
      spreadRadius: -8,
    ),
  ];

  /// Barely-there shadow for floating cards.
  static List<BoxShadow> soft(BuildContext context) => Theme.of(context).brightness == Brightness.dark
      ? const []
      : [BoxShadow(color: Colors.black.withValues(alpha: 0.045), blurRadius: 18, offset: const Offset(0, 6))];
}

class AppTheme {
  AppTheme._();

  static const _seed = Color(0xFF0B6E4F);

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness).copyWith(
      surface: isLight ? const Color(0xFFF4F6F3) : const Color(0xFF0D1110),
      surfaceContainerLowest: isLight ? Colors.white : const Color(0xFF151B19),
      surfaceContainerHighest: isLight ? const Color(0xFFE6EBE7) : const Color(0xFF243029),
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      fontFamily: Brand.fontFamily,
    );
    final text = base.textTheme;
    final outline = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: scheme.outlineVariant),
    );

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      extensions: [isLight ? StatusColors.light : StatusColors.dark],
      textTheme: text.copyWith(
        displaySmall: text.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1.2),
        headlineLarge: text.headlineLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1),
        headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8),
        headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4),
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(
          fontFamily: Brand.fontFamily,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: isLight ? 0.45 : 0.35)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: outline,
        enabledBorder: outline,
        focusedBorder: outline.copyWith(borderSide: BorderSide(color: scheme.primary, width: 1.6)),
        errorBorder: outline.copyWith(borderSide: BorderSide(color: scheme.error)),
        focusedErrorBorder: outline.copyWith(borderSide: BorderSide(color: scheme.error, width: 1.6)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontFamily: Brand.fontFamily, fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: const TextStyle(fontFamily: Brand.fontFamily, fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: const TextStyle(fontFamily: Brand.fontFamily, fontWeight: FontWeight.w700),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.6), space: 1, thickness: 1),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      tabBarTheme: TabBarThemeData(
        labelStyle: const TextStyle(fontFamily: Brand.fontFamily, fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(fontFamily: Brand.fontFamily, fontWeight: FontWeight.w500),
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: scheme.outlineVariant.withValues(alpha: 0.6),
      ),
      listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          textStyle: const TextStyle(fontFamily: Brand.fontFamily, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}
