import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/format_parsers.dart';
import '../../../data/models/encode_task.dart';
import '../../../data/services/gallery_service.dart';
import '../../../providers/active_encode_provider.dart';

/// Single queue row: status, name, progress bar (when running), actions.
/// Expands to reveal details and share options for completed tasks.
class QueueTile extends ConsumerStatefulWidget {
  const QueueTile({
    super.key,
    required this.task,
    this.onCancel,
    this.onRemove,
  });

  final VoidCallback? onCancel;
  final VoidCallback? onRemove;
  final EncodeTask task;

  @override
  ConsumerState<QueueTile> createState() => _QueueTileState();
}

class _QueueTileState extends ConsumerState<QueueTile> {
  bool _isExpanded = false;

  /// Builds the expandable details panel showing paths, duration, and share action.
  Widget _buildDetailsPanel(BuildContext context, EncodeTask task) {
    final duration = (task.startedAt != null && task.finishedAt != null)
        ? task.finishedAt!.difference(task.startedAt!)
        : Duration.zero;

    // Use sourceName to avoid showing long cache file_picker paths
    final sourceDisplay = task.sourceName ?? task.sourcePath;

    // If output path is in the cache directory, it means it was moved to the gallery
    final isOutputInCache = task.outputPath.contains('/cache/');
    final outputDisplay = isOutputInCache
        ? 'Saved to Device Gallery'
        : task.outputPath;

    return Padding(
      padding: const EdgeInsets.only(top: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DetailRow(label: 'Source', value: sourceDisplay),
          const SizedBox(height: 4),
          _DetailRow(label: 'Output', value: outputDisplay),
          const SizedBox(height: 4),
          _DetailRow(
            label: 'Processed',
            value: FormatParsers.formatDuration(duration.inSeconds),
          ),
          if (task.status == EncodeStatus.completed) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.share_outlined, size: 18),
                label: const Text('Share'),
                onPressed: () => ref
                    .read(galleryServiceProvider)
                    .share(task.outputPath, subject: task.sourceName),
              ),
            ),
          ],
          const Divider(height: 16),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final task = widget.task;
    final activeProgress = ref.watch(activeEncodeProvider);
    final progress =
        (task.status == EncodeStatus.running &&
            activeProgress?.taskId == task.id)
        ? activeProgress
        : null;

    // Only allow expansion if the task completed successfully
    final canExpand = task.status == EncodeStatus.completed;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: canExpand
            ? () => setState(() => _isExpanded = !_isExpanded)
            : null,
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
                  if (widget.onCancel != null)
                    IconButton(
                      tooltip: 'Cancel',
                      icon: const Icon(Icons.stop_circle_outlined),
                      onPressed: widget.onCancel,
                    ),
                  if (widget.onRemove != null)
                    IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: widget.onRemove,
                    ),
                  if (canExpand)
                    Icon(
                      _isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: theme.colorScheme.onSurfaceVariant,
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
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                child: _isExpanded && canExpand
                    ? _buildDetailsPanel(context, task)
                    : const SizedBox.shrink(),
              ),
            ],
          ),
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

/// Simple row for displaying key-value details in the expansion panel.
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label: ',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ),
      ],
    );
  }
}
