import 'package:flutter/material.dart';

import '../../../data/models/media_info.dart';

/// Read-only metadata summary card shown after probing the source.
class MediaInfoCard extends StatelessWidget {
  const MediaInfoCard({super.key, required this.info});
  final MediaInfo info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <(IconData, String, String)>[
      (Icons.aspect_ratio_outlined, 'Resolution', info.resolutionLabel),
      (Icons.timer_outlined, 'Duration', info.durationLabel),
      (Icons.movie_creation_outlined, 'Video', info.videoCodec ?? '—'),
      (Icons.graphic_eq_outlined, 'Audio', info.audioCodec ?? '—'),
      (Icons.folder_outlined, 'Container', info.container ?? '—'),
    ];

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Column(
          children: [
            for (final (icon, k, v) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      icon,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      k,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      v,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
