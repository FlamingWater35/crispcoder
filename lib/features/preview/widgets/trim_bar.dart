import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Interactive progress bar with optional trim handles for video editing.
/// Uses AnimatedBuilder to isolate repaints solely to the bar itself.
class TrimBar extends StatelessWidget {
  const TrimBar({
    super.key,
    required this.controller,
    required this.totalDuration,
    required this.startFraction,
    required this.endFraction,
    required this.trimMode,
    required this.onStartChanged,
    required this.onEndChanged,
    required this.onScrub,
  });

  final VideoPlayerController controller;
  final Duration totalDuration;
  final double startFraction;
  final double endFraction;
  final bool trimMode;

  final ValueChanged<double> onStartChanged;
  final ValueChanged<double> onEndChanged;
  final ValueChanged<double> onScrub;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return SizedBox(
          height: 40,
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final pos = controller.value.position;
              final playhead = totalDuration.inMilliseconds > 0
                  ? (pos.inMilliseconds / totalDuration.inMilliseconds).clamp(
                      0.0,
                      1.0,
                    )
                  : 0.0;
              return _buildStack(context, width, playhead);
            },
          ),
        );
      },
    );
  }

  /// Builds the layered stack: background track, selection highlight,
  /// scrub area, playhead, and (in trim mode) two drag handles.
  Widget _buildStack(BuildContext context, double width, double playhead) {
    final theme = Theme.of(context);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: 16,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Container(
              height: 8,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
        Positioned(
          top: 16,
          left: trimMode ? startFraction * width : 0,
          width: (trimMode ? (endFraction - startFraction) : playhead) * width,
          child: IgnorePointer(
            child: Container(
              height: 8,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => onScrub(d.localPosition.dx / width),
            onHorizontalDragUpdate: (d) => onScrub(d.localPosition.dx / width),
            child: const ColoredBox(color: Colors.transparent),
          ),
        ),
        Positioned(
          left: playhead * width - 1,
          top: 8,
          child: IgnorePointer(
            child: Container(
              width: 2,
              height: 24,
              color: theme.colorScheme.error,
            ),
          ),
        ),
        if (trimMode)
          _buildHandle(
            context,
            left: startFraction * width,
            semanticLabel: 'Start trim handle',
            onDrag: (delta) {
              final f = (startFraction + delta / width).clamp(
                0.0,
                endFraction - 0.01,
              );
              onStartChanged(f);
            },
          ),
        if (trimMode)
          _buildHandle(
            context,
            left: endFraction * width,
            semanticLabel: 'End trim handle',
            onDrag: (delta) {
              final f = (endFraction + delta / width).clamp(
                startFraction + 0.01,
                1.0,
              );
              onEndChanged(f);
            },
          ),
      ],
    );
  }

  /// Draggable trim handle with grip icon and accessibility label.
  Widget _buildHandle(
    BuildContext context, {
    required double left,
    required String semanticLabel,
    required ValueChanged<double> onDrag,
  }) {
    final theme = Theme.of(context);
    return Positioned(
      left: left - 12,
      top: 4,
      child: Semantics(
        label: semanticLabel,
        child: GestureDetector(
          onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
          child: Container(
            width: 24,
            height: 32,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.drag_handle_rounded,
              size: 16,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
