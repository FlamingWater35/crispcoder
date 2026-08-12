import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/utils/format_parsers.dart';
import '../../../core/utils/responsive.dart';
import '../../../data/models/encode_task.dart';
import '../../../data/models/transcode_preset.dart';
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final duration = (task.startedAt != null && task.finishedAt != null)
        ? task.finishedAt!.difference(task.startedAt!)
        : Duration.zero;

    // Use sourceName to avoid showing long cache file_picker paths
    final sourceDisplay = task.sourceName ?? task.sourcePath;

    // Only show the publish location when the output was actually published
    // via MediaStore — gate on the persisted URI, not just savedToGallery
    // (records from the old Gal→Pictures era set that flag without a
    // MediaStore entry). Audio publishes to Music/CrispCoder (the Audio
    // collection rejects DCIM); video/subtitle publish to DCIM/Videolation.
    // Show the published basename so the name/duplicate problem is easy to
    // spot. Unpublished outputs show the real path.
    final publishedDir = task.preset.outputType == OutputType.audio
        ? 'Music/CrispCoder'
        : 'DCIM/Videolation';
    final outputDisplay = task.publishedUri != null
        ? 'Saved to $publishedDir (${p.basename(task.outputPath)})'
        : task.outputPath;

    return Padding(
      padding: const EdgeInsets.only(top: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Distinct surfaced container so the expanded content reads as a
          // cohesive panel rather than floating rows.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DetailRow(label: 'Source', value: sourceDisplay),
                const SizedBox(height: 8),
                _DetailRow(label: 'Output', value: outputDisplay),
                const SizedBox(height: 8),
                _DetailRow(
                  label: 'Processed',
                  value: FormatParsers.formatDuration(duration.inSeconds),
                ),
                if (task.status == EncodeStatus.completed) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      icon: const Icon(Icons.share_outlined, size: 18),
                      label: const Text('Share'),
                      onPressed: () => _shareOutput(context, task),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 16),
        ],
      ),
    );
  }

  /// Shares the completed output file. When the output was published to
  /// MediaStore (DCIM/Videolation), share the persisted content:// URI —
  /// the private copy is deleted after publish, so the URI is the only
  /// remaining handle. Otherwise share the raw file path if it still exists.
  Future<void> _shareOutput(BuildContext context, EncodeTask task) async {
    if (task.publishedUri != null) {
      final ok = await ref
          .read(galleryServiceProvider)
          .share(task.publishedUri!, subject: task.displayTitle);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not share the published file — the MediaStore entry '
              'may have been removed.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    final file = File(task.outputPath);
    if (!await file.exists()) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Output file no longer exists:\n${task.outputPath}',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    await ref
        .read(galleryServiceProvider)
        .share(task.outputPath, subject: task.displayTitle);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final task = widget.task;
    final activeProgress = ref.watch(activeEncodeProvider);

    // Match active progress only if it belongs to this running task
    final progress =
        (task.status == EncodeStatus.running &&
            activeProgress?.taskId == task.id)
        ? activeProgress
        : null;

    final isRunning = task.status == EncodeStatus.running;
    // If running but no progress stats yet, FFmpeg is still initializing
    final isStarting = isRunning && progress == null;

    // Only allow expansion if the task completed successfully
    final canExpand = task.status == EncodeStatus.completed;

    // Wider gutters on large screens keep tiles aligned with the centered
    // column while phones keep the compact 12px margin.
    final width = MediaQuery.sizeOf(context).width;
    final hMargin = width >= Breakpoints.medium ? 32.0 : 12.0;

    return Card(
      margin: EdgeInsets.symmetric(horizontal: hMargin, vertical: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
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
                      // Title is the canonical artifact name: video shows the
                      // source, extractions show the output basename (e.g.
                      // "MySong_encoded.m4a") so a running audio job never
                      // shows as "Song.mp4". The Source row in the details
                      // panel still truthfully shows the source file.
                      task.displayTitle,
                      style: theme.textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Show loading spinner if preparing, otherwise show cancel button
                  if (isStarting)
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  else if (widget.onCancel != null)
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
                // The determinate indicator animates value changes natively
                // (no re-tween from zero on every progress tick).
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress.percent / 100,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(4),
                    color: theme.colorScheme.primary,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    _Meta(
                      label: progress.formattedPercent,
                      emphasized: true,
                    ),
                    // FPS only makes sense for video transcodes; extractions
                    // report 0 fps and would show "—".
                    if (task.preset.outputType == OutputType.video)
                      _Meta(label: progress.formattedFps),
                    _Meta(label: progress.formattedSpeed),
                    _Meta(label: 'ETA ${progress.formattedEta}'),
                    _Meta(label: progress.formattedBitrate),
                  ],
                ),
              ] else if (isStarting) ...[
                const SizedBox(height: 8),
                // Indicator that FFmpeg is spinning up before stats arrive
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Starting the process...',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
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
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (status) {
      EncodeStatus.pending => (Icons.schedule_rounded, scheme.onSurfaceVariant),
      EncodeStatus.running => (Icons.autorenew_rounded, scheme.primary),
      EncodeStatus.paused => (
        Icons.pause_circle_outline_rounded,
        scheme.tertiary,
      ),
      EncodeStatus.completed => (
        Icons.check_circle_rounded,
        scheme.tertiary,
      ),
      EncodeStatus.failed => (Icons.error_outline_rounded, scheme.error),
      EncodeStatus.cancelled => (
        Icons.cancel_outlined,
        scheme.onSurfaceVariant,
      ),
    };
    return Icon(icon, color: color);
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.label, this.emphasized = false});

  final String label;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label,
      style: theme.textTheme.labelSmall?.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
        fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
        color: emphasized ? theme.colorScheme.primary : null,
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
