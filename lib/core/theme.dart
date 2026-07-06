import 'package:flutter/material.dart';

// Hallmark - genre: editorial - macrostructure: Brutal Newsprint Workbench - design-system: design.md - designed-as-app

class AppTheme {
  static const Color scaffold = Color(0xFFF0E7D8);
  static const Color paper = Color(0xFFF7F0E4);
  static const Color paperAlt = Color(0xFFE7DDCC);
  static const Color paperMuted = Color(0xFFC4B59F);
  static const Color ink = Color(0xFF1F1A17);
  static const Color inkSoft = Color(0xFF5B5147);
  static const Color primaryGreen = Color(0xFF2D6A4F);
  static const Color accentPurple = Color(0xFF5C3D2E);
  static const Color accentGold = Color(0xFF9B6B26);
  static const Color accent = Color(0xFFB5472F);
  static const Color redAccent = Color(0xFFB5472F);
  static const Color focusBlue = Color(0xFF355C7D);
  static const Color textPrimary = ink;
  static const Color textSecondary = inkSoft;
  static const Color darkBg = scaffold;
  static const Color darkSurface = paper;
  static const Color darkCard = paperAlt;

  static const List<String> serifFallback = [
    'Iowan Old Style',
    'Palatino',
    'Times New Roman',
    'Georgia',
  ];

  static const List<String> sansFallback = [
    'Aptos',
    'Segoe UI',
    'Arial',
    'Helvetica',
  ];

  static const List<String> monoFallback = [
    'Consolas',
    'Courier New',
    'Menlo',
  ];

  static BoxDecoration panelDecoration({
    required Color color,
    bool accentTop = false,
  }) {
    return BoxDecoration(
      color: color,
      border: Border.all(color: ink, width: 2),
      boxShadow: const [
        BoxShadow(
          color: Color(0x33000000),
          offset: Offset(6, 6),
          blurRadius: 0,
        ),
      ],
      gradient: accentTop
          ? const LinearGradient(
              colors: [accent, accent, Colors.transparent, Colors.transparent],
              stops: [0, 0.03, 0.03, 1],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            )
          : null,
    );
  }

  static ThemeData get theme {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: scaffold,
      colorScheme: const ColorScheme.light(
        primary: ink,
        secondary: accent,
        surface: paper,
        error: redAccent,
      ),
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: paper,
        foregroundColor: ink,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: const CardThemeData(
        color: paper,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: ink, width: 2),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: ink,
        thickness: 1.5,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: ink,
        foregroundColor: paper,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: ink, width: 2),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: ink,
        contentTextStyle: TextStyle(
          color: paper,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          side: BorderSide(color: accent, width: 2),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: ink,
        circularTrackColor: paperMuted,
        linearTrackColor: paperMuted,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: paperAlt,
        side: const BorderSide(color: ink, width: 1.5),
        shape: const RoundedRectangleBorder(),
        labelStyle: const TextStyle(
          color: ink,
          fontWeight: FontWeight.w700,
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: paper,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: ink, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: ink, width: 2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: focusBlue, width: 3),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: redAccent, width: 2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: redAccent, width: 3),
        ),
        labelStyle: TextStyle(
          color: inkSoft,
          fontWeight: FontWeight.w700,
        ),
        hintStyle: TextStyle(
          color: inkSoft,
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: paper,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: ink, width: 2),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: const BorderSide(color: ink, width: 2),
          shape: const RoundedRectangleBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: ink,
          foregroundColor: paper,
          shape: const RoundedRectangleBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: ink,
          foregroundColor: paper,
          elevation: 0,
          shape: const RoundedRectangleBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          side: WidgetStateProperty.resolveWith(
            (_) => const BorderSide(color: ink, width: 2),
          ),
          shape: WidgetStateProperty.all(const RoundedRectangleBorder()),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? paper : ink,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? ink : paper,
          ),
          textStyle: WidgetStateProperty.all(
            const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: paper,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: ink, width: 2),
        ),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: ink,
          fontSize: 34,
          height: 0.94,
          fontWeight: FontWeight.w900,
          letterSpacing: -1.2,
          fontFamilyFallback: serifFallback,
          fontStyle: FontStyle.normal,
        ),
        headlineMedium: TextStyle(
          color: ink,
          fontSize: 28,
          height: 0.98,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.9,
          fontFamilyFallback: serifFallback,
          fontStyle: FontStyle.normal,
        ),
        titleLarge: TextStyle(
          color: ink,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          fontFamilyFallback: serifFallback,
          fontStyle: FontStyle.normal,
        ),
        titleMedium: TextStyle(
          color: ink,
          fontSize: 15,
          fontWeight: FontWeight.w800,
          fontFamilyFallback: sansFallback,
        ),
        bodyLarge: TextStyle(
          color: ink,
          fontSize: 15,
          height: 1.35,
          fontWeight: FontWeight.w600,
          fontFamilyFallback: sansFallback,
        ),
        bodyMedium: TextStyle(
          color: inkSoft,
          fontSize: 13.5,
          height: 1.4,
          fontWeight: FontWeight.w600,
          fontFamilyFallback: sansFallback,
        ),
        bodySmall: TextStyle(
          color: inkSoft,
          fontSize: 12,
          height: 1.35,
          fontWeight: FontWeight.w600,
          fontFamilyFallback: sansFallback,
        ),
        labelLarge: TextStyle(
          color: ink,
          fontSize: 13,
          fontWeight: FontWeight.w800,
          fontFamilyFallback: sansFallback,
        ),
        labelMedium: TextStyle(
          color: inkSoft,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          fontFamilyFallback: sansFallback,
        ),
        labelSmall: TextStyle(
          color: inkSoft,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          fontFamilyFallback: sansFallback,
        ),
      ),
    );
  }
}
