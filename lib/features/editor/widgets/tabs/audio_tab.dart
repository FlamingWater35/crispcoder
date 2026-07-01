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
    final standardAudioBitrates = [320, 256, 192, 160, 128, 96];
    final audioBitrateOptions = [...standardAudioBitrates];
    if (_originalAudioBitrate != null &&
        !audioBitrateOptions.contains(_originalAudioBitrate)) {
      audioBitrateOptions.add(_originalAudioBitrate!);
    }
    audioBitrateOptions.sort((a, b) => b.compareTo(a));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: SectionCard(
        title: 'Audio Configuration',
        icon: Icons.graphic_eq_outlined,
        children: [
          DropdownButtonFormField<AudioCodec>(
            decoration: const InputDecoration(
              labelText: 'Audio Codec',
              border: OutlineInputBorder(),
            ),
            initialValue: audioCodec,
            items: AudioCodec.values.map((c) {
              final isOrig = c.name == mediaInfo.audioCodec;
              return DropdownMenuItem(
                value: c,
                child: Text(
                  isOrig
                      ? '${c.name.toUpperCase()} (original)'
                      : c.name.toUpperCase(),
                ),
              );
            }).toList(),
            onChanged: onAudioCodecChanged,
          ),
          if (!isAudioCopy && !removeAudio) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              decoration: const InputDecoration(
                labelText: 'Audio Bitrate',
                border: OutlineInputBorder(),
              ),
              initialValue: audioBitrate,
              items: audioBitrateOptions.map((b) {
                final isOrig = b == _originalAudioBitrate;
                return DropdownMenuItem(
                  value: b,
                  child: Text(isOrig ? '$b kbps (original)' : '$b kbps'),
                );
              }).toList(),
              onChanged: onAudioBitrateChanged,
            ),
          ],
        ],
      ),
    );
  }
}
