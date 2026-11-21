import 'package:flutter/material.dart';

class AppColors {
  // Primary Brand Palette (globals.css spec)
  static const Color forestGreen = Color(0xFF0F5132); // Primary (Slaughterhouse Green)
  static const Color forestGreenHover = Color(0xFF0B3D26); // Primary Hover (Dark Forest Green)
  static const Color forestGreenDark = Color(0xFF0B3D26);
  static const Color accentTeal = Color(0xFF0F766E); // Accent (Teal Green)
  static const Color forestGreenLight = Color(0xFF0F766E);

  // Neutral Surfaces & Text
  static const Color appBg = Color(0xFFF4F6F9); // Main workspace canvas
  static const Color surface = Color(0xFFFFFFFF); // Cards, forms, tables
  static const Color ink = Color(0xFF0F172A); // Primary text (slate-900)
  static const Color muted = Color(0xFF475569); // Muted text (slate-600)
  static const Color borderInput = Color(0xFFCBD5E1); // Input borders (slate-300)
  static const Color borderDivider = Color(0xFFE2E8F0); // Card dividers (slate-200)

  // Semantic Status Tokens
  static const Color statusSuccessText = Color(0xFF047857); // emerald-700
  static const Color statusSuccessBg = Color(0xFFD1FAE5); // emerald-100
  static const Color statusWarningText = Color(0xFFB45309); // amber-700
  static const Color statusWarningBg = Color(0xFFFEF3C7); // amber-100
  static const Color statusDangerText = Color(0xFFB91C1C); // red-700
  static const Color statusDangerBg = Color(0xFFFEE2E2); // red-100

  // Legacy / Utility Tokens
  static const Color backgroundOverlay = Color(0x80000000);
  static const Color glassCard = Color(0xCC1E2828);
  static const Color white = Colors.white;
  static const Color grey = Colors.grey;

  // Dark Theme Palette
  static const Color darkBg = Color(0xFF0F172A);
  static const Color darkCard = Color(0xFF1E293B);
  static const Color darkBorder = Color(0xFF334155);
  static const Color darkText = Color(0xFFF8FAFC);
  static const Color darkSubtext = Color(0xFF94A3B8);
}

class AppTypography {
  static const String uiFontFamily = 'Segoe UI';
  static const List<String> uiFontFallback = [
    'system-ui',
    '-apple-system',
    'BlinkMacSystemFont',
    'Roboto',
    'sans-serif',
  ];

  static const String monoFontFamily = 'Courier New';
  static const List<String> monoFontFallback = ['Courier', 'monospace'];

  static TextStyle mono({
    double fontSize = 13.5,
    FontWeight fontWeight = FontWeight.w500,
    Color color = AppColors.ink,
    double? height,
  }) {
    return TextStyle(
      fontFamily: monoFontFamily,
      fontFamilyFallback: monoFontFallback,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
    );
  }
}

class AppTheme {
  static TextTheme _buildTextTheme(Color primaryColor, Color mutedColor) {
    TextStyle base(double size, FontWeight weight, Color color, {double? height}) => TextStyle(
          fontFamily: AppTypography.uiFontFamily,
          fontFamilyFallback: AppTypography.uiFontFallback,
          fontSize: size,
          fontWeight: weight,
          color: color,
          height: height,
        );

    return TextTheme(
      headlineLarge: base(28, FontWeight.w700, primaryColor, height: 1.2),
      headlineMedium: base(24, FontWeight.w700, primaryColor, height: 1.25), // h1: 24px Bold
      headlineSmall: base(20, FontWeight.w700, primaryColor, height: 1.3),
      titleLarge: base(18, FontWeight.w700, primaryColor, height: 1.3), // h2: 18px Bold
      titleMedium: base(16, FontWeight.w600, primaryColor, height: 1.35),
      titleSmall: base(14, FontWeight.w600, primaryColor, height: 1.35),
      bodyLarge: base(15.2, FontWeight.w400, primaryColor, height: 1.45),
      bodyMedium: base(14, FontWeight.w400, primaryColor, height: 1.45), // Body / Table: 14px
      bodySmall: base(13, FontWeight.w400, mutedColor, height: 1.4),
      labelLarge: base(14, FontWeight.w600, primaryColor), // Buttons: 14px Semibold
      labelMedium: base(12, FontWeight.w600, mutedColor), // Labels / Headers / Badges: 12px Semibold
      labelSmall: base(11, FontWeight.w600, mutedColor),
    );
  }

  static ThemeData get lightTheme {
    final textTheme = _buildTextTheme(AppColors.ink, AppColors.muted);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: AppTypography.uiFontFamily,
      fontFamilyFallback: AppTypography.uiFontFallback,
      scaffoldBackgroundColor: AppColors.appBg,
      dividerColor: AppColors.borderDivider,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.forestGreen,
        primary: AppColors.forestGreen,
        secondary: AppColors.accentTeal,
        surface: AppColors.surface,
        error: AppColors.statusDangerText,
        brightness: Brightness.light,
      ),
      textTheme: textTheme,
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return AppColors.forestGreen.withValues(alpha: 0.55);
            }
            if (states.contains(WidgetState.hovered) || states.contains(WidgetState.pressed)) {
              return AppColors.forestGreenHover;
            }
            return AppColors.forestGreen;
          }),
          foregroundColor: const WidgetStatePropertyAll(AppColors.white),
          elevation: const WidgetStatePropertyAll(0),
          minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(
              fontFamily: AppTypography.uiFontFamily,
              fontFamilyFallback: AppTypography.uiFontFallback,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.forestGreen,
          side: const BorderSide(color: AppColors.forestGreen),
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: const TextStyle(
            fontFamily: AppTypography.uiFontFamily,
            fontFamilyFallback: AppTypography.uiFontFallback,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.borderDivider),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        constraints: const BoxConstraints(minHeight: 46),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.borderInput),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.borderInput),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.forestGreen, width: 1.8),
        ),
        hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
        labelStyle: const TextStyle(
          color: AppColors.muted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  static ThemeData get darkTheme {
    final textTheme = _buildTextTheme(AppColors.darkText, AppColors.darkSubtext);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: AppTypography.uiFontFamily,
      fontFamilyFallback: AppTypography.uiFontFallback,
      scaffoldBackgroundColor: AppColors.darkBg,
      dividerColor: AppColors.darkBorder,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.forestGreen,
        primary: AppColors.accentTeal,
        brightness: Brightness.dark,
        surface: AppColors.darkCard,
      ),
      textTheme: textTheme,
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accentTeal,
          foregroundColor: AppColors.white,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: const TextStyle(
            fontFamily: AppTypography.uiFontFamily,
            fontFamilyFallback: AppTypography.uiFontFallback,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.accentTeal,
          side: const BorderSide(color: AppColors.accentTeal),
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.darkCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.darkBorder),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF0F172A),
        constraints: const BoxConstraints(minHeight: 46),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.accentTeal, width: 1.8),
        ),
        hintStyle: const TextStyle(color: Colors.white38),
        labelStyle: const TextStyle(color: AppColors.darkSubtext),
      ),
    );
  }
}
