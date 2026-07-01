import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/models/media_info.dart';
import '../../../../data/models/transcode_preset.dart';
import '../encoder_pref_info.dart';
import '../section_card.dart';

/// Video Tab: Codecs, Rate Control, Aspect Ratio, Resolution, Framerate
class VideoTab extends ConsumerWidget {
  const VideoTab({
    super.key,
    required this.mediaInfo,
    required this.videoCodec,
    required this.onVideoCodecChanged,
    required this.useCrf,
    required this.onUseCrfChanged,
    required this.crf,
    required this.onCrfChanged,
    required this.videoBitrate,
    required this.onVideoBitrateChanged,
    required this.hasVisualCrop,
    required this.cropWidth,
    required this.cropHeight,
    required this.onCropEditor,
    required this.aspectRatio,
    required this.onAspectRatioChanged,
    required this.resolution,
    required this.onResolutionChanged,
    required this.framerate,
    required this.onFramerateChanged,
  });

  final MediaInfo mediaInfo;
  final VideoCodec videoCodec;
  final void Function(VideoCodec?) onVideoCodecChanged;
  final bool useCrf;
  final void Function(Set<bool>) onUseCrfChanged;
  final int crf;
  final void Function(double) onCrfChanged;
  final int videoBitrate;
  final void Function(String) onVideoBitrateChanged;
  final bool hasVisualCrop;
  final double? cropWidth;
  final double? cropHeight;
  final VoidCallback? onCropEditor;
  final String? aspectRatio;
  final void Function(String?) onAspectRatioChanged;
  final int? resolution;
  final void Function(int?) onResolutionChanged;
  final int? framerate;
  final void Function(int?) onFramerateChanged;

  bool get _isVideoCopy => videoCodec == VideoCodec.copy;
  int? get _originalRes => mediaInfo.height;
  int? get _originalFps => mediaInfo.frameRate?.round();

  String? get _originalAspectRatio {
    final w = mediaInfo.width;
    final h = mediaInfo.height;
    if (w == null || h == null || w == 0 || h == 0) return null;
    int gcd(int a, int b) => b == 0 ? a : gcd(b, a % b);
    final g = gcd(w, h);
    return '${w ~/ g}:${h ~/ g}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final standardAspectRatios = ['16:9', '4:3', '1:1', '9:16', '21:9'];
    final standardResolutions = [2160, 1440, 1080, 720, 480, 360];

    final fpsOptions = [24, 25, 30, 60];
    if (_originalFps != null && !fpsOptions.contains(_originalFps)) {
      fpsOptions.add(_originalFps!);
    }
    fpsOptions.sort();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCard(
            title: 'Video Configuration',
            icon: Icons.videocam_outlined,
            children: [
              DropdownButtonFormField<VideoCodec>(
                decoration: const InputDecoration(
                  labelText: 'Video Codec',
                  border: OutlineInputBorder(),
                ),
                initialValue: videoCodec,
                items: VideoCodec.values.map((c) {
                  final isOrig = c.name == mediaInfo.videoCodec;
                  return DropdownMenuItem(
                    value: c,
                    child: Text(
                      isOrig
                          ? '${c.name.toUpperCase()} (original)'
                          : c.name.toUpperCase(),
                    ),
                  );
                }).toList(),
                onChanged: onVideoCodecChanged,
              ),
              const SizedBox(height: 8),
              const EncoderPrefInfo(),
              if (!_isVideoCopy) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Rate Control',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('CRF')),
                    ButtonSegment(value: false, label: Text('Bitrate')),
                  ],
                  selected: {useCrf},
                  onSelectionChanged: onUseCrfChanged,
                ),
                if (useCrf) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      SizedBox(
                        width: 56,
                        child: Text(
                          'CRF $crf',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          value: crf.toDouble(),
                          min: 0,
                          max: 51,
                          divisions: 51,
                          label: crf.toString(),
                          onChanged: onCrfChanged,
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    decoration: const InputDecoration(
                      labelText: 'Video Bitrate (kbps)',
                      border: OutlineInputBorder(),
                    ),
                    initialValue: videoBitrate.toString(),
                    keyboardType: TextInputType.number,
                    onChanged: onVideoBitrateChanged,
                  ),
                ],
              ],
            ],
          ),
          if (!_isVideoCopy) ...[
            const SizedBox(height: 16),
            SectionCard(
              title: 'Aspect Ratio & Resolution',
              icon: Icons.aspect_ratio_outlined,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.crop_rounded),
                    label: Text(
                      hasVisualCrop ? 'Edit Visual Crop' : 'Crop Visually',
                    ),
                    onPressed: onCropEditor,
                  ),
                ),
                if (hasVisualCrop)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Custom crop applied (${(cropWidth! * 100).toStringAsFixed(0)}% x ${(cropHeight! * 100).toStringAsFixed(0)}%)',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  decoration: const InputDecoration(
                    labelText: 'Aspect Ratio',
                    border: OutlineInputBorder(),
                  ),
                  initialValue: aspectRatio,
                  items: [
                    DropdownMenuItem<String?>(
                      value: _originalAspectRatio,
                      child: Text(
                        _originalAspectRatio != null
                            ? '$_originalAspectRatio (Original)'
                            : 'Original',
                      ),
                    ),
                    for (final ar in standardAspectRatios)
                      if (ar != _originalAspectRatio)
                        DropdownMenuItem<String?>(value: ar, child: Text(ar)),
                  ],
                  onChanged: onAspectRatioChanged,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                  decoration: const InputDecoration(
                    labelText: 'Resolution',
                    border: OutlineInputBorder(),
                  ),
                  initialValue: resolution,
                  items: [
                    DropdownMenuItem<int?>(
                      value: _originalRes,
                      child: Text(
                        _originalRes != null
                            ? '${_originalRes}p (Original)'
                            : 'Original',
                      ),
                    ),
                    for (final r in standardResolutions)
                      if (r != _originalRes)
                        DropdownMenuItem<int?>(value: r, child: Text('${r}p')),
                  ],
                  onChanged: onResolutionChanged,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  decoration: const InputDecoration(
                    labelText: 'Framerate',
                    border: OutlineInputBorder(),
                  ),
                  initialValue: framerate,
                  items: fpsOptions.map((f) {
                    final isOrig = f == _originalFps;
                    return DropdownMenuItem<int>(
                      value: f,
                      child: Text(isOrig ? '$f fps (original)' : '$f fps'),
                    );
                  }).toList(),
                  onChanged: onFramerateChanged,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
