import 'package:flutter/material.dart';

import '../../../data/models/media_info.dart';

/// Formats a raw ffprobe container string into a friendly display label.
///
/// ffprobe's format name is often a comma-separated list (e.g.
/// "mov,mp4,m4a,3gp,3g2,mj2"). We take the first (primary) token and
/// uppercase it for a clean "MP4" / "MKV" label.
String _friendlyContainer(String? raw) {
  if (raw == null || raw.isEmpty) return '—';
  return raw.split(',').first.trim().toUpperCase();
}

/// Read-only metadata summary card shown after probing the source.
class MediaInfoCard extends StatelessWidget {
  const MediaInfoCard({super.key, required this.info});
  final MediaInfo info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final containerLabel = _friendlyContainer(info.container);
    final rows = <(IconData, String, String)>[
      (Icons.aspect_ratio_outlined, 'Resolution', info.resolutionLabel),
      (Icons.timer_outlined, 'Duration', info.durationLabel),
      (Icons.movie_creation_outlined, 'Video', info.videoCodec ?? '—'),
      (Icons.graphic_eq_outlined, 'Audio', info.audioCodec ?? '—'),
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
            // Container as a friendly chip: primary format name + icon.
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Icon(
                    Icons.folder_outlined,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Container',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      containerLabel,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSecondaryContainer,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
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
