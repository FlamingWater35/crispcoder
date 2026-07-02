import 'package:flutter/material.dart';

import '../../../../data/models/media_info.dart';
import '../../../../data/models/transcode_preset.dart';
import '../section_card.dart';

/// Audio Tab: Audio Codec and Bitrate selection
class AudioTab extends StatelessWidget {
  const AudioTab({
    super.key,
    required this.mediaInfo,
    required this.audioCodec,
    required this.onAudioCodecChanged,
    required this.audioBitrate,
    required this.onAudioBitrateChanged,
    required this.isAudioCopy,
    required this.removeAudio,
  });

  final MediaInfo mediaInfo;
  final AudioCodec audioCodec;
  final void Function(AudioCodec?) onAudioCodecChanged;
  final int audioBitrate;
  final void Function(int?) onAudioBitrateChanged;
  final bool isAudioCopy;
  final bool removeAudio;

  int? get _originalAudioBitrate => mediaInfo.audioBitrateBitsPerSec != null
      ? mediaInfo.audioBitrateBitsPerSec! ~/ 1000
      : null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );

    final standardAudioBitrates = [512, 320, 256, 192, 160, 128, 96, 64];
    final audioBitrateOptions = [...standardAudioBitrates];
    if (_originalAudioBitrate != null &&
        !audioBitrateOptions.contains(_originalAudioBitrate)) {
      audioBitrateOptions.add(_originalAudioBitrate!);
    }
    audioBitrateOptions.sort((a, b) => b.compareTo(a));

    final showBitrate =
        !isAudioCopy && !removeAudio && audioCodec != AudioCodec.flac;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: SectionCard(
        title: 'Audio Configuration',
        icon: Icons.graphic_eq_outlined,
        children: [
          Text('Audio Codec', style: labelStyle),
          const SizedBox(height: 8),
          // Codec Chips
          Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            children: AudioCodec.values.map((c) {
              final isOrig = c.name == mediaInfo.audioCodec;
              return ChoiceChip(
                label: Text(
                  isOrig
                      ? '${c.name.toUpperCase()} (Orig)'
                      : c.name.toUpperCase(),
                ),
                selected: audioCodec == c,
                onSelected: (_) => onAudioCodecChanged(c),
              );
            }).toList(),
          ),
          if (showBitrate) ...[
            const SizedBox(height: 16),
            Text('Audio Bitrate', style: labelStyle),
            const SizedBox(height: 8),
            // Bitrate Chips
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: audioBitrateOptions.map((b) {
                final isOrig = b == _originalAudioBitrate;
                return ChoiceChip(
                  label: Text(isOrig ? '$b kbps (Orig)' : '$b kbps'),
                  selected: audioBitrate == b,
                  onSelected: (_) => onAudioBitrateChanged(b),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}
