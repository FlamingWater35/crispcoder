import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Central Material 3 design system for CrispCoder.
///
/// Builds light and dark [ThemeData] from a single seed color so every screen
/// shares one coherent palette, then applies component-level polish:
/// elevated-but-quiet cards, rounded inputs/buttons, and a subtle material
/// motion feel (smooth theme transitions, standardized easing).
abstract final class AppTheme {
  /// Brand seed — a vibrant, "crisp" blue.
  static const Color seed = Color(0xFF2B5CD9);

  /// Standard motion easing used across the app (M3 "emphasized").
  static const Curve emphasized = Curves.easeOutCubic;

  /// Duration for small widget-level transitions.
  static const Duration fast = Duration(milliseconds: 200);

  /// Duration for larger transitions (theme changes, card reflow).
  static const Duration medium = Duration(milliseconds: 300);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      // Slightly reduce chroma for calmer surfaces while keeping vivid
      // primary/secondary accents.
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
    );

    // Material 3 shape scale: small radii for inputs, medium for cards,
    // large for sheets/dialogs.
    final radiusSmall = 12.0;
    final radiusMedium = 16.0;
    final radiusLarge = 28.0;

    final cardTheme = CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
    );

    final inputTheme = InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSmall),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSmall),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSmall),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSmall),
        borderSide: BorderSide(color: scheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSmall),
        borderSide: BorderSide(color: scheme.error, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );

    // Note: only shape/textStyle are themed globally. The background color is
    // intentionally left to the M3 defaults so `FilledButton.tonal` keeps its
    // secondaryContainer look instead of being recolored by a global theme.
    final buttonTheme = FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );

    final outlinedButtonTheme = OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
        ),
        side: BorderSide(color: scheme.outline),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );

    final textButtonTheme = TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );

    final appBarTheme = AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: true,
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      titleTextStyle: base.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.25,
        color: scheme.onSurface,
      ),
    );

    final chipTheme = ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      side: BorderSide.none,
      backgroundColor: scheme.surfaceContainerHighest,
      labelStyle: base.textTheme.labelMedium?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    );

    final dividerTheme = DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: 0.7),
      thickness: 1,
      space: 1,
    );

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      cardTheme: cardTheme,
      inputDecorationTheme: inputTheme,
      filledButtonTheme: buttonTheme,
      outlinedButtonTheme: outlinedButtonTheme,
      textButtonTheme: textButtonTheme,
      appBarTheme: appBarTheme,
      chipTheme: chipTheme,
      dividerTheme: dividerTheme,
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        circularTrackColor: scheme.surfaceContainerHighest,
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        height: 68,
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.secondaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.onSecondaryContainer
                : scheme.onSurfaceVariant,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => base.textTheme.labelMedium?.copyWith(
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? scheme.onSurface
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 2,
        highlightElevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
        ),
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusLarge)),
        ),
      ),
      searchBarTheme: SearchBarThemeData(
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(
          scheme.surfaceContainerHigh,
        ),
        side: WidgetStatePropertyAll(
          BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSmall + 4),
          ),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
