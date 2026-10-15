import 'package:flutter/material.dart';

/// Brand constants, identical in both modes.
class AppColors {
  static const navy = Color(0xFF0B1F33);
  static const navyDeep = Color(0xFF061423);
  static const blue = Color(0xFF1E3A5F);
  static const amber = Color(0xFFD97706);
  static const amberBright = Color(0xFFF59E0B);
}

const appFontFamily = 'Inter';

/// Semantic design tokens; screens read colors from here, never from constants.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.isDark,
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.textPrimary,
    required this.textMuted,
    required this.primary,
    required this.onPrimary,
    required this.accent,
    required this.accentSoft,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.violet,
    required this.chartGrid,
    required this.chartAlt,
    required this.chartSeries,
    required this.shadow,
  });

  final bool isDark;
  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color border;
  final Color textPrimary;
  final Color textMuted;
  final Color primary;
  final Color onPrimary;
  final Color accent;
  final Color accentSoft;
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;
  final Color violet;
  final Color chartGrid;

  /// Secondary/comparison series (previous year, averages).
  final Color chartAlt;
  final List<Color> chartSeries;
  final Color shadow;

  static const light = AppPalette(
    isDark: false,
    background: Color(0xFFF4F6FA),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF1F4F9),
    border: Color(0xFFE2E8F0),
    textPrimary: Color(0xFF0F172A),
    textMuted: Color(0xFF64748B),
    primary: AppColors.navy,
    onPrimary: Colors.white,
    accent: AppColors.amber,
    accentSoft: Color(0xFFFEF3C7),
    success: Color(0xFF0F766E),
    warning: Color(0xFFB45309),
    danger: Color(0xFFDC2626),
    info: Color(0xFF2563EB),
    violet: Color(0xFF7C3AED),
    chartGrid: Color(0xFFE2E8F0),
    chartAlt: Color(0xFFE67E22),
    chartSeries: [
      AppColors.navy,
      Color(0xFF0F766E),
      Color(0xFF7C3AED),
      Color(0xFFBE123C),
      Color(0xFF2563EB),
    ],
    shadow: Color(0x140F172A),
  );

  static const dark = AppPalette(
    isDark: true,
    background: Color(0xFF0B1220),
    surface: Color(0xFF111A2E),
    surfaceAlt: Color(0xFF17223A),
    border: Color(0xFF24314D),
    textPrimary: Color(0xFFE6EDF7),
    textMuted: Color(0xFF93A3BC),
    primary: Color(0xFF8DB4F0),
    onPrimary: Color(0xFF0B1220),
    accent: AppColors.amberBright,
    accentSoft: Color(0xFF3A2A0C),
    success: Color(0xFF2DD4BF),
    warning: Color(0xFFFBBF24),
    danger: Color(0xFFF87171),
    info: Color(0xFF60A5FA),
    violet: Color(0xFFC4B5FD),
    chartGrid: Color(0xFF24314D),
    chartAlt: Color(0xFFFB923C),
    chartSeries: [
      Color(0xFF8DB4F0),
      Color(0xFF2DD4BF),
      Color(0xFFC4B5FD),
      Color(0xFFFB7185),
      Color(0xFF60A5FA),
    ],
    shadow: Color(0x00000000),
  );

  /// Quinzaine (en_cours/cloturee/a_venir) and quotation statuses.
  Color status(String status) => switch (status) {
        'en_cours' => accent,
        'cloturee' => success,
        'published' => success,
        'no_data' => danger,
        'not_published_yet' => warning,
        'weekend' => textMuted.withValues(alpha: 0.7),
        _ => textMuted,
      };

  /// Translucent background for a colored element (chips, icon bubbles).
  Color tint(Color c) => c.withValues(alpha: isDark ? 0.18 : 0.10);

  Color seriesAt(int i) => chartSeries[i % chartSeries.length];

  @override
  AppPalette copyWith() => this;

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) =>
      other is AppPalette && t >= 0.5 ? other : this;
}

extension PaletteContext on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
}

ThemeData buildLightTheme() => _buildTheme(AppPalette.light);

ThemeData buildDarkTheme() => _buildTheme(AppPalette.dark);

ThemeData _buildTheme(AppPalette p) {
  final brightness = p.isDark ? Brightness.dark : Brightness.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.navy,
    brightness: brightness,
  ).copyWith(
    primary: p.primary,
    onPrimary: p.onPrimary,
    secondary: p.accent,
    onSecondary: Colors.white,
    tertiary: p.success,
    surface: p.surface,
    onSurface: p.textPrimary,
    onSurfaceVariant: p.textMuted,
    surfaceContainerLowest: p.surface,
    surfaceContainerLow: p.surface,
    surfaceContainer: p.surface,
    surfaceContainerHigh: p.surfaceAlt,
    surfaceContainerHighest: p.surfaceAlt,
    outline: p.border,
    outlineVariant: p.border,
    error: p.danger,
  );

  final base = ThemeData(brightness: brightness, useMaterial3: true);
  final text = base.textTheme
      .apply(fontFamily: appFontFamily, bodyColor: p.textPrimary, displayColor: p.textPrimary)
      .copyWith(
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          fontFamily: appFontFamily,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
          color: p.textPrimary,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontFamily: appFontFamily,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: p.textPrimary,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontFamily: appFontFamily,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
          color: p.textPrimary,
        ),
      );

  final radius12 = BorderRadius.circular(12);
  OutlineInputBorder inputBorder(Color c, [double w = 1]) =>
      OutlineInputBorder(borderRadius: radius12, borderSide: BorderSide(color: c, width: w));

  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: p.background,
    canvasColor: p.surface,
    textTheme: text,
    extensions: [p],
    dividerColor: p.border,
    dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      foregroundColor: p.textPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: appFontFamily,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: p.textPrimary,
      ),
    ),
    cardTheme: CardThemeData(
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: p.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surfaceAlt,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: inputBorder(p.border),
      enabledBorder: inputBorder(p.border),
      disabledBorder: inputBorder(p.border.withValues(alpha: 0.5)),
      focusedBorder: inputBorder(p.primary, 1.6),
      errorBorder: inputBorder(p.danger),
      labelStyle: TextStyle(color: p.textMuted),
      hintStyle: TextStyle(color: p.textMuted.withValues(alpha: 0.7)),
      prefixIconColor: p.textMuted,
      suffixIconColor: p.textMuted,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 68,
      indicatorColor: p.accentSoft,
      indicatorShape: const StadiumBorder(),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected) ? p.accent : p.textMuted,
          size: 24,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontFamily: appFontFamily,
          fontSize: 11.5,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? p.textPrimary : p.textMuted,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.primary,
        foregroundColor: p.onPrimary,
        minimumSize: const Size(64, 46),
        shape: RoundedRectangleBorder(borderRadius: radius12),
        textStyle: const TextStyle(fontFamily: appFontFamily, fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.textPrimary,
        minimumSize: const Size(64, 46),
        side: BorderSide(color: p.border),
        shape: RoundedRectangleBorder(borderRadius: radius12),
        textStyle: const TextStyle(fontFamily: appFontFamily, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.isDark ? p.primary : p.info,
        textStyle: const TextStyle(fontFamily: appFontFamily, fontWeight: FontWeight.w600),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: radius12)),
        side: WidgetStatePropertyAll(BorderSide(color: p.border)),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.accentSoft : p.surface,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.accent : p.textMuted,
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontFamily: appFontFamily, fontWeight: FontWeight.w600),
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.surfaceAlt,
      selectedColor: p.accentSoft,
      side: BorderSide(color: p.border),
      shape: const StadiumBorder(),
      labelStyle: TextStyle(fontFamily: appFontFamily, color: p.textPrimary, fontSize: 13),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.white : p.textMuted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.accent : p.surfaceAlt,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.transparent : p.border,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.accent : Colors.transparent,
      ),
      side: BorderSide(color: p.textMuted, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.accent : p.textMuted,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: p.border,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: radius12,
        side: BorderSide(color: p.border),
      ),
      textStyle: TextStyle(fontFamily: appFontFamily, color: p.textPrimary, fontSize: 14),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: radius12),
      contentTextStyle: const TextStyle(fontFamily: appFontFamily, color: Colors.white),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: p.accent,
      foregroundColor: Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dataTableTheme: DataTableThemeData(
      headingRowColor: WidgetStatePropertyAll(p.surfaceAlt),
      headingTextStyle: TextStyle(
        fontFamily: appFontFamily,
        fontWeight: FontWeight.w700,
        fontSize: 12,
        color: p.textMuted,
      ),
      dataTextStyle: TextStyle(fontFamily: appFontFamily, fontSize: 13, color: p.textPrimary),
      dividerThickness: 0.6,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: p.textMuted,
      textColor: p.textPrimary,
      shape: RoundedRectangleBorder(borderRadius: radius12),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.accent),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: p.isDark ? p.surfaceAlt : AppColors.navy,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: TextStyle(
        fontFamily: appFontFamily,
        color: p.isDark ? p.textPrimary : Colors.white,
        fontSize: 12,
      ),
    ),
  );
}
