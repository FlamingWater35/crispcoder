import 'package:flutter/material.dart';

/// Breakpoints for the app's responsive layout, following Material 3's
/// window-size classes (compact / medium / expanded).
abstract final class Breakpoints {
  /// Phones in portrait and small landscape.
  static const double compact = 600;

  /// Tablets in portrait, small laptops.
  static const double medium = 840;

  /// Tablets in landscape, desktop.
  static const double expanded = 1200;
}

/// Maximum content width so cards stay readable on very wide screens.
const double maxContentWidth = 960;

/// Centers [child] and caps its width to [maxContentWidth] for large screens.
Widget centeredContent({
  required Widget child,
  EdgeInsetsGeometry? padding,
}) {
  return Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: maxContentWidth),
      child: padding != null ? Padding(padding: padding, child: child) : child,
    ),
  );
}
