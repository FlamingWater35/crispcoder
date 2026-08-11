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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        elevation: 2,
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
            Expanded(
              child: Text(
                'Encoding',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            if (!isStarting)
              TextButton.icon(
                onPressed: onCancel,
                icon: const Icon(Icons.stop_circle_outlined, size: 18),
                label: const Text('Cancel'),
              ),
          ],
        ),
        const SizedBox(height: 4),
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
                    style: theme.textTheme.titleMedium,
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
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        _Meta(label: progress!.formattedFps),
                        _Meta(label: progress!.formattedSpeed),
                        _Meta(label: 'ETA ${progress!.formattedEta}'),
                        _Meta(label: progress!.formattedBitrate),
                      ],
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
              color: scheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.schedule_outlined, color: scheme.onSurfaceVariant),
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
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  task!.sourceName ?? task!.sourcePath.split('/').last,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Chip(
            label: const Text('Queued'),
            labelStyle: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            visualDensity: VisualDensity.compact,
            backgroundColor: scheme.surfaceContainerHighest,
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
          child: Icon(Icons.movie_creation_outlined,
              color: scheme.onSurfaceVariant),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Nothing encoding right now',
            style: theme.textTheme.titleSmall,
          ),
        ),
      ],
    );
  }
}

/// Circular progress ring with the current percentage centered.
class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.percent});

  final double? percent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final value = percent == null ? null : percent! / 100;

    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 72,
            height: 72,
            child: CircularProgressIndicator(
              value: value,
              strokeWidth: 7,
              backgroundColor: scheme.surfaceContainerHighest,
              color: scheme.primary,
            ),
          ),
          Text(
            value == null ? '—' : '${percent!.toStringAsFixed(0)}%',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}
