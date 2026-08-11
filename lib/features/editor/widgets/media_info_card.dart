import 'package:flutter/material.dart';

import '../../../data/models/media_info.dart';

/// Splits a raw ffprobe container string into up to [max] friendly labels.
///
/// ffprobe's format name is a comma-separated list (e.g.
/// "mov,mp4,m4a,3gp,3g2,mj2"). We take the first [max] tokens, uppercase each,
/// and drop generic/duplicate entries for a clean "MP4" / "MKV" display.
List<String> _friendlyContainers(String? raw, {int max = 3}) {
  if (raw == null || raw.isEmpty) return const [];
  final seen = <String>{};
  final result = <String>[];
  for (final token in raw.split(',')) {
    final label = token.trim().toUpperCase();
    if (label.isEmpty || seen.contains(label)) continue;
    seen.add(label);
    result.add(label);
    if (result.length >= max) break;
  }
  return result;
}

/// Read-only metadata summary card shown after probing the source.
///
/// Every stat — resolution, duration, video, audio, and container — is a
/// uniform small raised card, so the section reads as one coherent grid.
class MediaInfoCard extends StatelessWidget {
  const MediaInfoCard({super.key, required this.info});
  final MediaInfo info;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final containers = _friendlyContainers(info.container);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        // Generous bottom padding so the source details section breathes
        // before the editing tabs below.
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Source details',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                // Two stat cards per row on narrow screens, three on wide.
                final perRow = constraints.maxWidth >= 380 ? 3 : 2;
                final gap = 8.0;
                final width = (constraints.maxWidth - (perRow - 1) * gap) /
                    perRow;
                final stats = [
                  _StatCard(
                    icon: Icons.aspect_ratio_outlined,
                    label: 'Resolution',
                    value: info.resolutionLabel,
                  ),
                  _StatCard(
                    icon: Icons.timer_outlined,
                    label: 'Duration',
                    value: info.durationLabel,
                  ),
                  _StatCard(
                    icon: Icons.videocam_outlined,
                    label: 'Video',
                    value: info.videoCodec ?? '—',
                  ),
                  _StatCard(
                    icon: Icons.graphic_eq_outlined,
                    label: 'Audio',
                    value: info.audioCodec ?? '—',
                  ),
                ];
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final card in stats)
                      SizedBox(width: width, child: card),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            // Container as a uniform stat card (up to 3 badges inside).
            _StatCard(
              icon: Icons.folder_outlined,
              label: 'Container',
              value: containers.isEmpty
                  ? '—'
                  : containers.join(' · '),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small raised stat card: icon, label, and value underneath.
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
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
              Icon(icon, size: 14, color: scheme.primary),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
