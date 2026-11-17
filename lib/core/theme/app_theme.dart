import 'package:flutter/material.dart';

/// Sistema de diseño — identidad institucional UAGRM.
///
/// Los mismos valores que la plataforma web (`globals.css`). Tres familias de
/// color con usos que no se mezclan:
///   · Marca (azul marino y borgoña de las siglas): estructura y acciones.
///   · Estado (verde, ámbar, rojo): SOLO para decir cómo está un vehículo, un
///     escaneo o una orden. Nunca como decoración.
///   · Neutros: todo lo demás.
///
/// El borgoña no se usa en botones: el rojo ya significa "requiere
/// evaluación", y un botón rojo junto a una falla confunde.
abstract final class AppColors {
  // Marca
  static const navy = Color(0xFF000878);
  static const navyPressed = Color(0xFF132266);
  static const navySoft = Color(0xFFEEF0FA);
  static const crimson = Color(0xFF8A0817);

  // Superficies y texto
  static const app = Color(0xFFFAFBFD);
  static const surface = Color(0xFFFFFFFF);
  static const line = Color(0xFFE2E8F0);
  static const lineStrong = Color(0xFFCBD5E1);
  static const ink = Color(0xFF0F172A);
  static const ink2 = Color(0xFF475569);
  static const ink3 = Color(0xFF64748B);

  /// Solo íconos inactivos: no alcanza el contraste para texto.
  static const inkOff = Color(0xFF94A3B8);

  // Estado
  static const ok = Color(0xFF15803D);
  static const okSoft = Color(0xFFDCFCE7);
  static const warn = Color(0xFFB45309);
  static const warnSoft = Color(0xFFFEF3C7);
  static const danger = Color(0xFFB91C1C);
  static const dangerSoft = Color(0xFFFEE2E2);
}

/// Los controles son más rectos que los paneles: la forma dice qué es qué.
abstract final class AppRadius {
  static const control = 6.0;
  static const panel = 8.0;
}

abstract final class AppFonts {
  static const sans = 'IBMPlexSans';
  static const mono = 'IBMPlexMono';
}

abstract final class AppText {
  /// Placas, VIN y códigos de falla: se leen carácter por carácter.
  static const code = TextStyle(
    fontFamily: AppFonts.mono,
    fontFeatures: [FontFeature.tabularFigures()],
    letterSpacing: 0.1,
  );

  /// Cifras alineadas en contadores y lecturas.
  static const nums = TextStyle(
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

abstract final class AppTheme {
  static ThemeData get light {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.navy,
      onPrimary: Colors.white,
      primaryContainer: AppColors.navySoft,
      onPrimaryContainer: AppColors.navy,
      secondary: AppColors.navy,
      onSecondary: Colors.white,
      secondaryContainer: AppColors.navySoft,
      onSecondaryContainer: AppColors.navy,
      tertiary: AppColors.crimson,
      onTertiary: Colors.white,
      error: AppColors.danger,
      onError: Colors.white,
      errorContainer: AppColors.dangerSoft,
      onErrorContainer: AppColors.danger,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      onSurfaceVariant: AppColors.ink2,
      outline: AppColors.lineStrong,
      outlineVariant: AppColors.line,
      // Sin tinte de elevación: las superficies son blancas y las separa un borde.
      surfaceTint: Colors.transparent,
      surfaceContainerLowest: AppColors.surface,
      surfaceContainerLow: AppColors.surface,
      surfaceContainer: AppColors.surface,
      surfaceContainerHigh: AppColors.app,
      surfaceContainerHighest: AppColors.line,
      inverseSurface: AppColors.ink,
      onInverseSurface: Colors.white,
      inversePrimary: AppColors.navySoft,
      scrim: AppColors.ink,
    );

    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.control),
    );
    final panelShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.panel),
      side: const BorderSide(color: AppColors.line),
    );
    const buttonText = TextStyle(
      fontFamily: AppFonts.sans,
      fontSize: 15,
      fontWeight: FontWeight.w500,
    );

    OutlineInputBorder inputBorder(Color color, [double width = 1]) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: AppFonts.sans,
      scaffoldBackgroundColor: AppColors.app,
      dividerColor: AppColors.line,
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.ink,
        displayColor: AppColors.ink,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.navy,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: AppFonts.sans,
          fontSize: 19,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: AppColors.navy,
        ),
        shape: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      // Sin sombra: sobre un fondo tan claro, el borde alcanza para separar.
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: panelShape,
        clipBehavior: Clip.antiAlias,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.line,
        thickness: 1,
        space: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.navy,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.navy.withValues(alpha: 0.5),
          disabledForegroundColor: Colors.white,
          minimumSize: const Size(64, 48),
          shape: controlShape,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.ink,
          minimumSize: const Size(64, 48),
          side: const BorderSide(color: AppColors.lineStrong),
          shape: controlShape,
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.navy,
          shape: controlShape,
          textStyle: buttonText.copyWith(fontSize: 14),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: AppColors.navy),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        labelStyle: const TextStyle(color: AppColors.ink2),
        floatingLabelStyle: const TextStyle(color: AppColors.navy),
        helperStyle: const TextStyle(color: AppColors.ink3),
        helperMaxLines: 3,
        errorMaxLines: 3,
        prefixIconColor: AppColors.ink3,
        suffixIconColor: AppColors.ink3,
        border: inputBorder(AppColors.lineStrong),
        enabledBorder: inputBorder(AppColors.lineStrong),
        focusedBorder: inputBorder(AppColors.navy, 2),
        errorBorder: inputBorder(AppColors.danger),
        focusedErrorBorder: inputBorder(AppColors.danger, 2),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        elevation: 0,
        height: 68,
        indicatorColor: AppColors.navySoft,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? AppColors.navy
                : AppColors.ink3,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              fontFamily: AppFonts.sans,
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? AppColors.navy : AppColors.ink2,
            );
          },
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink,
        contentTextStyle: const TextStyle(
          fontFamily: AppFonts.sans,
          fontSize: 14,
          color: Colors.white,
        ),
        actionTextColor: Colors.white,
        shape: controlShape,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.panel),
        ),
        titleTextStyle: const TextStyle(
          fontFamily: AppFonts.sans,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.navy,
        linearTrackColor: AppColors.line,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : AppColors.ink3,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.navy
              : AppColors.line,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.navy
              : AppColors.lineStrong,
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.ink3,
        textColor: AppColors.ink,
      ),
    );
  }
}
