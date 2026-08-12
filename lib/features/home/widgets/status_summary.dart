import 'package:flutter/material.dart';

/// Row of stat chips summarizing the current queue state.
///
/// Chips resolve their accent colors from the theme's color scheme (instead
/// of hardcoded material colors) and animate value changes with an
/// [AnimatedSwitcher] so counters tick smoothly.
class StatusSummary extends StatelessWidget {
  const StatusSummary({
    super.key,
    required this.running,
    required this.queued,
    required this.completed,
    this.failed = 0,
  });

  final int running;
  final int queued;
  final int completed;
  final int failed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chips = <Widget>[
      _StatChip(
        icon: Icons.autorenew_rounded,
        color: scheme.primary,
        container: scheme.primaryContainer.withValues(alpha: 0.45),
        label: 'Running',
        value: running,
      ),
      _StatChip(
        icon: Icons.schedule_rounded,
        color: scheme.onSurfaceVariant,
        container: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        label: 'Queued',
        value: queued,
      ),
      _StatChip(
        icon: Icons.check_circle_rounded,
        color: scheme.tertiary,
        container: scheme.tertiaryContainer.withValues(alpha: 0.45),
        label: 'Completed',
        value: completed,
      ),
      _StatChip(
        icon: Icons.error_outline_rounded,
        color: scheme.error,
        container: scheme.errorContainer.withValues(alpha: 0.45),
        label: 'Failed',
        value: failed,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Wide screens: keep the single row.
          if (constraints.maxWidth >= 600) {
            const spacing = 10.0;
            return Row(children: [
              for (var i = 0; i < chips.length; i++) ...[
                if (i > 0) const SizedBox(width: spacing),
                Expanded(child: chips[i]),
              ],
            ]);
          }
          // Phones: 2×2 grid so labels never truncate.
          const gap = 8.0;
          final itemWidth = (constraints.maxWidth - gap) / 2;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final c in chips) SizedBox(width: itemWidth, child: c),
            ],
          );
        },
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.color,
    required this.container,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final Color container;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: container,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SizeTransition(
                      sizeFactor: animation,
                      alignment: Alignment.topCenter,
                      child: child,
                    ),
                  ),
                  child: Text(
                    '$value',
                    key: ValueKey(value),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
