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
/// Tapping the header collapses/expands the stats to save vertical space.
class MediaInfoCard extends StatefulWidget {
  const MediaInfoCard({super.key, required this.info});
  final MediaInfo info;

  @override
  State<MediaInfoCard> createState() => _MediaInfoCardState();
}

class _MediaInfoCardState extends State<MediaInfoCard> {
  // Collapsed by default so the loaded editor shows the tabs without the
  // stats taking up vertical space.
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final containers = _friendlyContainers(widget.info.container);
    final stats = [
      _StatCard(
        icon: Icons.aspect_ratio_outlined,
        label: 'Resolution',
        value: widget.info.resolutionLabel,
      ),
      _StatCard(
        icon: Icons.timer_outlined,
        label: 'Duration',
        value: widget.info.durationLabel,
      ),
      _StatCard(
        icon: Icons.videocam_outlined,
        label: 'Video',
        value: widget.info.videoCodec ?? '—',
      ),
      _StatCard(
        icon: Icons.graphic_eq_outlined,
        label: 'Audio',
        value: widget.info.audioCodec ?? '—',
      ),
    ];

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tappable header row.
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 10, 10),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 20, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Source File Details',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.0 : 0.5,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Animated expand/collapse of the stats.
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LayoutBuilder(
                          builder: (context, constraints) {
                            // Two stat cards per row on narrow screens, three
                            // on wide.
                            final perRow =
                                constraints.maxWidth >= 380 ? 3 : 2;
                            final gap = 8.0;
                            final width =
                                (constraints.maxWidth - (perRow - 1) * gap) /
                                perRow;
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
                        // Container as a uniform stat card.
                        _StatCard(
                          icon: Icons.folder_outlined,
                          label: 'Container',
                          value: containers.isEmpty
                              ? '—'
                              : containers.join(' · '),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
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
