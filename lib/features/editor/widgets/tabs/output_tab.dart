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
    final originalContainer = _mapContainer(mediaInfo.container);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: SectionCard(
        title: 'Container Configuration',
        icon: Icons.folder_outlined,
        children: [
          DropdownButtonFormField<ContainerFormat>(
            decoration: const InputDecoration(
              labelText: 'Format',
              border: OutlineInputBorder(),
            ),
            initialValue: container,
            items: ContainerFormat.values.map((c) {
              final isOrig = c == originalContainer;
              return DropdownMenuItem(
                value: c,
                child: Text(
                  isOrig
                      ? '${c.name.toUpperCase()} (original)'
                      : c.name.toUpperCase(),
                ),
              );
            }).toList(),
            onChanged: onContainerChanged,
          ),
          if (container == ContainerFormat.mp4)
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
      ),
    );
  }
}
