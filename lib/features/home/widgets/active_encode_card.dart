import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/encode_progress.dart';
import '../../../data/models/encode_task.dart';
import '../../../providers/active_encode_provider.dart';
import '../../../providers/queue_provider.dart';

/// Spotlight card for the encode in progress.
///
/// Always shown: while a task is running it displays the live progress ring
/// with % / fps / speed / ETA / bitrate and a cancel action; otherwise it
/// falls back to an "Up next" (first pending task) or idle state.
class ActiveEncodeCard extends ConsumerWidget {
  const ActiveEncodeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(queueProvider);
    final activeProgress = ref.watch(activeEncodeProvider);

    final running = queue
        .where((t) => t.status == EncodeStatus.running)
        .firstOrNull;
    final nextPending = queue
        .where((t) => t.status == EncodeStatus.pending)
        .firstOrNull;

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: running != null
                ? [
                    scheme.primaryContainer.withValues(alpha: 0.9),
                    scheme.surfaceContainerHigh,
                    scheme.surfaceContainerHigh,
                  ]
                : [
                    scheme.surfaceContainerHigh,
                    scheme.surfaceContainerLow,
                  ],
          ),
          border: Border.all(
            color: running != null
                ? scheme.primary.withValues(alpha: 0.35)
                : scheme.outlineVariant.withValues(alpha: 0.5),
          ),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: running != null
              ? _RunningSpotlight(
                  task: running,
                  progress: activeProgress,
                  onCancel: () =>
                      ref.read(queueProvider.notifier).cancelActive(),
                )
              : _IdleState(task: nextPending),
        ),
      ),
    );
  }
}

/// Live progress ring + meta for the currently running encode.
class _RunningSpotlight extends StatelessWidget {
  const _RunningSpotlight({
    required this.task,
    required this.progress,
    required this.onCancel,
  });

  final EncodeTask task;
  final EncodeProgress? progress;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isStarting = progress == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bolt_rounded, size: 14, color: scheme.primary),
                  const SizedBox(width: 4),
                  Text(
                    'Encoding',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            if (!isStarting)
              TextButton.icon(
                onPressed: onCancel,
                icon: const Icon(Icons.stop_circle_outlined, size: 18),
                label: const Text('Cancel'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _ProgressRing(percent: progress?.percent),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.sourceName ?? task.sourcePath.split('/').last,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  if (isStarting)
                    Text(
                      'Starting the process...',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.primary,
                        fontStyle: FontStyle.italic,
                      ),
                    )
                  else ...[
                    // Stats as small raised cards with icons — each metric
                    // gets its own chip with a distinct accent color.
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final cards = [
                          _StatCard(
                            icon: Icons.speed_rounded,
                            label: 'FPS',
                            value: progress!.formattedFps,
                            color: scheme.primary,
                          ),
                          _StatCard(
                            icon: Icons.fast_forward_rounded,
                            label: 'Speed',
                            value: progress!.formattedSpeed,
                            color: scheme.tertiary,
                          ),
                          _StatCard(
                            icon: Icons.timer_outlined,
                            label: 'ETA',
                            value: progress!.formattedEta,
                            color: scheme.error,
                          ),
                          _StatCard(
                            icon: Icons.data_usage_rounded,
                            label: 'Bitrate',
                            value: progress!.formattedBitrate,
                            color: scheme.secondary,
                          ),
                        ];
                        // Two cards per row on narrow screens, four on wide.
                        final perRow = constraints.maxWidth >= 380 ? 4 : 2;
                        final gap = 8.0;
                        final width =
                            (constraints.maxWidth - (perRow - 1) * gap) /
                            perRow;
                        return Wrap(
                          spacing: gap,
                          runSpacing: gap,
                          children: [
                            for (final card in cards)
                              SizedBox(width: width, child: card),
                          ],
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Fallback shown when nothing is currently running.
class _IdleState extends StatelessWidget {
  const _IdleState({required this.task});

  final EncodeTask? task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (task != null) {
      return Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.schedule_rounded,
              color: scheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Up next',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  task!.sourceName ?? task!.sourcePath.split('/').last,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Chip(
            label: const Text('Queued'),
            labelStyle: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSecondaryContainer,
            ),
            visualDensity: VisualDensity.compact,
            backgroundColor: scheme.secondaryContainer,
            side: BorderSide.none,
          ),
        ],
      );
    }

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.movie_creation_outlined,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Nothing encoding right now',
            style: theme.textTheme.titleSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// Circular progress ring with the current percentage centered.
///
/// The ring animates from its previous value to the new one on each progress
/// tick (via a [Tween] from the last target), so it fills smoothly instead of
/// restarting from zero on every rebuild.
class _ProgressRing extends StatefulWidget {
  const _ProgressRing({required this.percent});

  final double? percent;

  @override
  State<_ProgressRing> createState() => _ProgressRingState();
}

class _ProgressRingState extends State<_ProgressRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _curve;

  /// Value the ring currently displays; the begin of the next tween.
  double _displayed = 0;

  /// Latest target value; null while indeterminate (no progress yet).
  double? _target;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _target = _targetOf(widget.percent);
    if (_target != null) _displayed = _target!;
  }

  @override
  void didUpdateWidget(_ProgressRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newTarget = _targetOf(widget.percent);
    if (newTarget == null) return; // indeterminate — keep current value
    if (_target != null && (newTarget - _target!).abs() < 0.0001) return;
    _displayed = _target ?? _displayed;
    _target = newTarget;
    _controller.forward(from: 0);
  }

  static double? _targetOf(double? percent) =>
      percent == null ? null : percent / 100;

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final value = widget.percent == null ? null : widget.percent! / 100;

    return SizedBox(
      width: 76,
      height: 76,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 76,
            height: 76,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => CircularProgressIndicator(
                value: value == null
                    ? null
                    : Tween<double>(begin: _displayed, end: _target!)
                        .evaluate(_curve),
                strokeWidth: 7,
                strokeCap: StrokeCap.round,
                backgroundColor: scheme.surfaceContainerHighest,
                color: scheme.primary,
              ),
            ),
          ),
          Text(
            value == null ? '—' : '${widget.percent!.toStringAsFixed(0)}%',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Small raised stat card: icon, value, and a label underneath.
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;

  /// Distinct accent color for this stat (icon + label + value).
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
