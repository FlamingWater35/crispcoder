import 'package:flutter/material.dart';

import '../../../../data/models/media_info.dart';
import '../../../../data/models/transcode_preset.dart';
import '../section_card.dart';

/// Output Tab: Container format and Faststart optimization
class OutputTab extends StatelessWidget {
  const OutputTab({
    super.key,
    required this.mediaInfo,
    required this.container,
    required this.onContainerChanged,
    required this.faststart,
    required this.onFaststartChanged,
  });

  final MediaInfo mediaInfo;
  final ContainerFormat container;
  final void Function(ContainerFormat?) onContainerChanged;
  final bool faststart;
  final void Function(bool) onFaststartChanged;

  ContainerFormat _mapContainer(String? format) {
    if (format == null) return ContainerFormat.mp4;
    if (format.contains('mp4') || format.contains('mov')) {
      return ContainerFormat.mp4;
    }
    if (format.contains('matroska') || format.contains('mkv')) {
      return ContainerFormat.mkv;
    }
    if (format.contains('webm')) return ContainerFormat.webm;
    return ContainerFormat.mp4;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );

    final originalContainer = _mapContainer(mediaInfo.container);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: SectionCard(
        title: 'Container Configuration',
        icon: Icons.folder_outlined,
        children: [
          Text('Format', style: labelStyle),
          const SizedBox(height: 8),
          // Container Format Chips
          Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            children: ContainerFormat.values.map((c) {
              final isOrig = c == originalContainer;
              return ChoiceChip(
                label: Text(
                  isOrig
                      ? '${c.name.toUpperCase()} (Orig)'
                      : c.name.toUpperCase(),
                ),
                selected: container == c,
                onSelected: (_) => onContainerChanged(c),
              );
            }).toList(),
          ),
          if (container == ContainerFormat.mp4) ...[
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Faststart (Web Optimized)'),
              subtitle: const Text(
                'Move moov atom to file start for streaming',
              ),
              value: faststart,
              onChanged: onFaststartChanged,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ],
      ),
    );
  }
}
