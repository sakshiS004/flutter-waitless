import 'package:flutter/material.dart';

import 'constants.dart';

class AppTheme {

  AppTheme._();

  static ThemeData get lightTheme {

    return ThemeData(

      useMaterial3: true,

      brightness: Brightness.light,

      // ── Color Scheme ──────────────────────────────────────────────────────

      colorScheme: ColorScheme.fromSeed(

        seedColor: AppColors.primary,
        brightness: Brightness.light,
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        surface: AppColors.surface,
        error: AppColors.error,
        onPrimary: AppColors.white,
        onSecondary: AppColors.white,
        onSurface: AppColors.textPrimary,

      ),

      // ── Scaffold ──────────────────────────────────────────────────────────

      scaffoldBackgroundColor: AppColors.background,
     // ── Typography (Nunito — clean medical sans-serif) ────────────────────

     //fontFamily: 'Nunito',
      textTheme: const TextTheme(

       // Display
        displayLarge: TextStyle(fontSize: 57, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: -0.5),
        displayMedium: TextStyle(fontSize: 45, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        displaySmall: TextStyle(fontSize: 36, fontWeight: FontWeight.w600, color: AppColors.textPrimary),

       // Headline

        headlineLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.5),
        headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary),

       // Title
        titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary, letterSpacing: 0.1),
        titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary, letterSpacing: 0.1),

// Body

        bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: AppColors.textPrimary, height: 1.5),

        bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.textSecondary, height: 1.5),

        bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.textSecondary, height: 1.4),

// Label

        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.white, letterSpacing: 0.5),

        labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),

        labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textHint),

      ),



// ── Input Decoration ──────────────────────────────────────────────────

      inputDecorationTheme: InputDecorationTheme(

        filled: true,

        fillColor: AppColors.inputFill,

        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),

// Default border

        border: OutlineInputBorder(

          borderRadius: BorderRadius.circular(14),

          borderSide: const BorderSide(color: AppColors.divider, width: 1.0),

        ),

// Enabled (idle)

        enabledBorder: OutlineInputBorder(

          borderRadius: BorderRadius.circular(14),

          borderSide: const BorderSide(color: AppColors.divider, width: 1.0),

        ),

// Focused

        focusedBorder: OutlineInputBorder(

          borderRadius: BorderRadius.circular(14),

          borderSide: const BorderSide(color: AppColors.primary, width: 1.8),

        ),

// Error

        errorBorder: OutlineInputBorder(

          borderRadius: BorderRadius.circular(14),

          borderSide: const BorderSide(color: AppColors.error, width: 1.4),

        ),

        focusedErrorBorder: OutlineInputBorder(

          borderRadius: BorderRadius.circular(14),

          borderSide: const BorderSide(color: AppColors.error, width: 1.8),

        ),

// Label & hint styles

        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textSecondary),

        hintStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.textHint),

        floatingLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary),

        errorStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.error),

      ),



// ── Elevated Button ───────────────────────────────────────────────────

      elevatedButtonTheme: ElevatedButtonThemeData(

        style: ElevatedButton.styleFrom(

          backgroundColor: AppColors.primary,

          foregroundColor: AppColors.white,

          minimumSize: const Size(double.infinity, 52),

          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),

          elevation: 0,

          shadowColor: Colors.transparent,

          textStyle: const TextStyle(

            fontFamily: 'Nunito',

            fontSize: 15,

            fontWeight: FontWeight.w700,

            letterSpacing: 0.4,

          ),

        ),

      ),



// ── Text Button ───────────────────────────────────────────────────────

      textButtonTheme: TextButtonThemeData(

        style: TextButton.styleFrom(

          foregroundColor: AppColors.primary,

          textStyle: const TextStyle(

            fontFamily: 'Nunito',

            fontSize: 14,

            fontWeight: FontWeight.w600,

          ),

        ),

      ),



// ── Card ──────────────────────────────────────────────────────────────

      cardTheme: CardThemeData(

        color: AppColors.white,

        elevation: 0,

        shape: RoundedRectangleBorder(

          borderRadius: BorderRadius.circular(20),

          side: const BorderSide(color: AppColors.divider, width: 1.0),

        ),

        margin: EdgeInsets.zero,

      ),



// ── AppBar ────────────────────────────────────────────────────────────

      appBarTheme: const AppBarTheme(

        backgroundColor: AppColors.white,

        foregroundColor: AppColors.textPrimary,

        elevation: 0,

        scrolledUnderElevation: 1,

        centerTitle: true,

        titleTextStyle: TextStyle(

          fontFamily: 'Nunito',

          fontSize: 18,

          fontWeight: FontWeight.w700,

          color: AppColors.textPrimary,

        ),

      ),



// ── Divider ───────────────────────────────────────────────────────────

      dividerTheme: const DividerThemeData(

        color: AppColors.divider,

        thickness: 1.0,

        space: 1.0,

      ),

    );

  }

}