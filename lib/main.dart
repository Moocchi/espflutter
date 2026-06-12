import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/app_state.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: const GanciApp(),
    ),
  );
}

/// ─── Theme Provider for Light/Dark switching ───
class ThemeProvider extends ChangeNotifier {
  final ThemeMode _mode = ThemeMode.light;
  ThemeMode get mode => _mode;
  bool get isDark => false;

  void toggle() {}

  void setMode(ThemeMode m) {}
}

/// ─── Design Tokens from Stitch Design System ───
/// Usage: `GanciColors.of(context).primary` or static `GanciColors.primary`
class GanciColors {
  GanciColors._();

  // ── DARK THEME TOKENS ──
  static const Color background = Color(0xFF0D0D1A);
  static const Color surface = Color(0xFF12121F);
  static const Color surfaceContainer = Color(0xFF1E1E2C);
  static const Color surfaceContainerHigh = Color(0xFF292937);
  static const Color surfaceContainerHighest = Color(0xFF343342);
  static const Color surfaceBright = Color(0xFF383847);

  static Color glassCard = const Color(0xFF1C1C38).withOpacity(0.85);
  static Color glassBorder = const Color(0xFF7C6BF0).withOpacity(0.15);
  static Color glassGlow = const Color(0xFF7C6BF0).withOpacity(0.08);

  static const Color primary = Color(0xFF7C6BF0);
  static const Color primaryLight = Color(0xFFC7BFFF);
  static const Color primaryContainer = Color(0xFF8E7FFF);
  static const Color onPrimary = Color(0xFF2B009E);

  static const Color secondary = Color(0xFF41EEC2);
  static const Color secondaryContainer = Color(0xFF00D4AA);

  static const Color tertiary = Color(0xFFC5C3E8);

  static const Color error = Color(0xFFFF5B6A);
  static const Color warning = Color(0xFFFFB547);
  static const Color success = Color(0xFF41EEC2);

  static const Color textPrimary = Color(0xFFE3E0F4);
  static const Color textSecondary = Color(0xFFC9C4D6);
  static const Color textMuted = Color(0xFF928E9F);
  static const Color textOnPrimary = Colors.white;

  static const Color outline = Color(0xFF928E9F);
  static const Color outlineVariant = Color(0xFF474554);

  // ── LIGHT THEME TOKENS ──
  static const Color lightBackground = Color(0xFFF8F9FF);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceContainer = Color(0xFFE5EEFF);
  static const Color lightSurfaceContainerLow = Color(0xFFEFF4FF);
  static const Color lightSurfaceContainerHigh = Color(0xFFDCE9FF);
  static const Color lightSurfaceContainerHighest = Color(0xFFD3E4FE);
  static const Color lightSurfaceBright = Color(0xFFF8F9FF);

  static Color lightGlassCard = const Color(0xFFFFFFFF).withOpacity(0.92);
  static Color lightGlassBorder = const Color(0xFFC7C4D8);
  static Color lightGlassGlow = const Color(0xFF3525CD).withOpacity(0.05);

  static const Color lightPrimary = Color(0xFF3525CD);
  static const Color lightPrimaryLight = Color(0xFF4F46E5);
  static const Color lightPrimaryContainer = Color(0xFF4F46E5);

  static const Color lightTextPrimary = Color(0xFF0B1C30);
  static const Color lightTextSecondary = Color(0xFF464555);
  static const Color lightTextMuted = Color(0xFF777587);

  static const Color lightOutline = Color(0xFF777587);
  static const Color lightOutlineVariant = Color(0xFFC7C4D8);
}

/// ─── Theme-Aware Color Access ───
class GanciTheme {
  final bool isDark;
  const GanciTheme({required this.isDark});

  Color get bg => isDark ? GanciColors.background : GanciColors.lightBackground;
  Color get surface => isDark ? GanciColors.surface : GanciColors.lightSurface;
  Color get surfaceContainer => isDark ? GanciColors.surfaceContainer : GanciColors.lightSurfaceContainer;
  Color get surfaceContainerLow => isDark ? GanciColors.surfaceContainer : GanciColors.lightSurfaceContainerLow;
  Color get surfaceContainerHigh => isDark ? GanciColors.surfaceContainerHigh : GanciColors.lightSurfaceContainerHigh;
  Color get surfaceContainerHighest => isDark ? GanciColors.surfaceContainerHighest : GanciColors.lightSurfaceContainerHighest;
  Color get surfaceBright => isDark ? GanciColors.surfaceBright : GanciColors.lightSurfaceBright;

  Color get glassCard => isDark ? GanciColors.glassCard : GanciColors.lightGlassCard;
  Color get glassBorder => isDark ? GanciColors.glassBorder : GanciColors.lightGlassBorder;
  Color get glassGlow => isDark ? GanciColors.glassGlow : GanciColors.lightGlassGlow;

  Color get primary => isDark ? GanciColors.primary : GanciColors.lightPrimary;
  Color get primaryLight => isDark ? GanciColors.primaryLight : GanciColors.lightPrimaryLight;
  Color get primaryContainer => isDark ? GanciColors.primaryContainer : GanciColors.lightPrimaryContainer;

  Color get textPrimary => isDark ? GanciColors.textPrimary : GanciColors.lightTextPrimary;
  Color get textSecondary => isDark ? GanciColors.textSecondary : GanciColors.lightTextSecondary;
  Color get textMuted => isDark ? GanciColors.textMuted : GanciColors.lightTextMuted;

  Color get outline => isDark ? GanciColors.outline : GanciColors.lightOutline;
  Color get outlineVariant => isDark ? GanciColors.outlineVariant : GanciColors.lightOutlineVariant;

  static GanciTheme of(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    return GanciTheme(isDark: isDark);
  }
}

ThemeData _buildDarkTheme() {
  return ThemeData.dark().copyWith(
    scaffoldBackgroundColor: GanciColors.background,
    colorScheme: const ColorScheme.dark(
      primary: GanciColors.primary,
      secondary: GanciColors.secondary,
      surface: GanciColors.surface,
      error: GanciColors.error,
      onPrimary: Colors.white,
      onSurface: GanciColors.textPrimary,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      iconTheme: IconThemeData(color: GanciColors.textPrimary),
      titleTextStyle: TextStyle(fontFamily: 'Inter', fontSize: 20, fontWeight: FontWeight.w600, color: GanciColors.textPrimary),
    ),
    cardTheme: CardThemeData(
      color: GanciColors.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: GanciColors.glassBorder)),
      elevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: GanciColors.primary.withOpacity(0.08),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: GanciColors.glassBorder)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: GanciColors.glassBorder)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: GanciColors.primaryContainer, width: 1.5)),
      labelStyle: const TextStyle(color: GanciColors.textMuted, fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w500),
      hintStyle: TextStyle(color: GanciColors.textMuted.withOpacity(0.6), fontFamily: 'Inter'),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: GanciColors.primary,
      thumbColor: GanciColors.primaryLight,
      inactiveTrackColor: GanciColors.outlineVariant,
      overlayColor: GanciColors.primary.withOpacity(0.12),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      trackHeight: 3,
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? GanciColors.primary : Colors.transparent),
      checkColor: WidgetStateProperty.all(Colors.white),
      side: BorderSide(color: GanciColors.outlineVariant, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? GanciColors.primary : GanciColors.outlineVariant),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? GanciColors.primaryLight : GanciColors.textMuted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? GanciColors.primary.withOpacity(0.4) : GanciColors.outlineVariant.withOpacity(0.3)),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    textTheme: const TextTheme(
      displayLarge: TextStyle(fontFamily: 'Inter', fontSize: 40, fontWeight: FontWeight.w700, color: GanciColors.textPrimary, letterSpacing: -0.5),
      headlineLarge: TextStyle(fontFamily: 'Inter', fontSize: 32, fontWeight: FontWeight.w600, color: GanciColors.textPrimary),
      headlineMedium: TextStyle(fontFamily: 'Inter', fontSize: 24, fontWeight: FontWeight.w600, color: GanciColors.textPrimary),
      titleLarge: TextStyle(fontFamily: 'Inter', fontSize: 20, fontWeight: FontWeight.w600, color: GanciColors.textPrimary),
      titleMedium: TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w600, color: GanciColors.textPrimary),
      bodyLarge: TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w400, color: GanciColors.textSecondary),
      bodyMedium: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w400, color: GanciColors.textSecondary),
      bodySmall: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w400, color: GanciColors.textMuted),
      labelLarge: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: GanciColors.textPrimary, letterSpacing: 0.5),
      labelSmall: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w500, color: GanciColors.textMuted, letterSpacing: 0.8),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: GanciColors.surfaceContainer,
      contentTextStyle: const TextStyle(color: GanciColors.textPrimary, fontFamily: 'Inter'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: GanciColors.glassBorder)),
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: GanciColors.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: GanciColors.glassBorder)),
      titleTextStyle: const TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w600, color: GanciColors.textPrimary),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: GanciColors.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: GanciColors.primary.withOpacity(0.4),
        disabledForegroundColor: Colors.white60,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    dividerTheme: DividerThemeData(color: GanciColors.outlineVariant.withOpacity(0.4), thickness: 1),
  );
}

ThemeData _buildLightTheme() {
  return ThemeData.light().copyWith(
    scaffoldBackgroundColor: GanciColors.lightBackground,
    colorScheme: const ColorScheme.light(
      primary: Color(0xFF5B48CD),
      secondary: Color(0xFF00A88A),
      surface: Colors.white,
      error: Color(0xFFB42318),
      onPrimary: Colors.white,
      onSurface: Color(0xFF1A1A2E),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      iconTheme: IconThemeData(color: Color(0xFF3F4670)),
      titleTextStyle: TextStyle(fontFamily: 'Inter', fontSize: 20, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E)),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: GanciColors.lightGlassBorder)),
      elevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF0EEFF),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFD4D1FF))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFD4D1FF))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF6252E7), width: 1.5)),
      labelStyle: const TextStyle(color: Color(0xFF6D7385), fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w500),
      hintStyle: const TextStyle(color: Color(0xFF9AA0B3), fontFamily: 'Inter'),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: const Color(0xFF5B48CD),
      thumbColor: const Color(0xFF6252E7),
      inactiveTrackColor: const Color(0xFFD8D4FF),
      overlayColor: const Color(0xFF5B48CD).withOpacity(0.12),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      trackHeight: 3,
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? const Color(0xFF5B48CD) : Colors.transparent),
      checkColor: WidgetStateProperty.all(Colors.white),
      side: const BorderSide(color: Color(0xFFB4B9C8), width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? const Color(0xFF5B48CD) : const Color(0xFF9AA0B3)),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? const Color(0xFF5B48CD).withOpacity(0.3) : const Color(0xFFD4D1FF)),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    textTheme: const TextTheme(
      displayLarge: TextStyle(fontFamily: 'Inter', fontSize: 40, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E), letterSpacing: -0.5),
      headlineLarge: TextStyle(fontFamily: 'Inter', fontSize: 32, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E)),
      headlineMedium: TextStyle(fontFamily: 'Inter', fontSize: 24, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E)),
      titleLarge: TextStyle(fontFamily: 'Inter', fontSize: 20, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E)),
      bodyLarge: TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w400, color: Color(0xFF3F4670)),
      bodyMedium: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w400, color: Color(0xFF3F4670)),
      bodySmall: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w400, color: Color(0xFF6D7385)),
      labelLarge: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E), letterSpacing: 0.5),
      labelSmall: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w500, color: Color(0xFF6D7385), letterSpacing: 0.8),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Colors.white,
      contentTextStyle: const TextStyle(color: Color(0xFF1A1A2E), fontFamily: 'Inter'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFD4D1FF))),
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFFD4D1FF))),
      titleTextStyle: const TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF5B48CD),
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFF5B48CD).withOpacity(0.4),
        disabledForegroundColor: Colors.white60,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    dividerTheme: const DividerThemeData(color: Color(0xFFE8E4FF), thickness: 1),
  );
}

class GanciApp extends StatelessWidget {
  const GanciApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    // Update system UI based on theme
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: themeProvider.isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: themeProvider.isDark ? const Color(0xFF0D0D1A) : const Color(0xFFF7F5FF),
      systemNavigationBarIconBrightness: themeProvider.isDark ? Brightness.light : Brightness.dark,
    ));

    return MaterialApp(
      title: 'Ganci - ESP32 Image Tools',
      debugShowCheckedModeBanner: false,
      theme: _buildLightTheme(),
      darkTheme: _buildDarkTheme(),
      themeMode: themeProvider.mode,
      home: const HomeScreen(),
    );
  }
}
