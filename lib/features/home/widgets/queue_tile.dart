import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/encode_task.dart';
import '../../../providers/active_encode_provider.dart';

/// Single queue row: status, name, progress bar (when running), actions.
class QueueTile extends ConsumerWidget {
  const QueueTile({
    super.key,
    required this.task,
    this.onCancel,
    this.onRemove,
  });

  final EncodeTask task;
  final VoidCallback? onCancel;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final activeProgress = ref.watch(activeEncodeProvider);
    final progress =
        (task.status == EncodeStatus.running &&
            activeProgress?.taskId == task.id)
        ? activeProgress
        : null;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _StatusIcon(status: task.status),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    task.sourceName ?? task.sourcePath.split('/').last,
                    style: theme.textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (onCancel != null)
                  IconButton(
                    tooltip: 'Cancel',
                    icon: const Icon(Icons.stop_circle_outlined),
                    onPressed: onCancel,
                  ),
                if (onRemove != null)
                  IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: onRemove,
                  ),
              ],
            ),
            if (progress != null) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: progress.percent / 100),
              const SizedBox(height: 6),
              Wrap(
                spacing: 12,
                children: [
                  _Meta(label: progress.formattedPercent),
                  _Meta(label: progress.formattedFps),
                  _Meta(label: progress.formattedSpeed),
                  _Meta(label: 'ETA ${progress.formattedEta}'),
                  _Meta(label: progress.formattedBitrate),
                ],
              ),
            ] else if (task.status == EncodeStatus.failed) ...[
              const SizedBox(height: 8),
              Text(
                task.errorMessage ?? 'Transcode failed.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});
  final EncodeStatus status;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (status) {
      EncodeStatus.pending => (Icons.schedule_outlined, Colors.grey),
      EncodeStatus.running => (Icons.autorenew, Colors.blue),
      EncodeStatus.paused => (Icons.pause_circle_outline, Colors.orange),
      EncodeStatus.completed => (Icons.check_circle, Colors.green),
      EncodeStatus.failed => (Icons.error_outline, Colors.red),
      EncodeStatus.cancelled => (Icons.cancel_outlined, Colors.grey),
    };
    return Icon(icon, color: color);
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
