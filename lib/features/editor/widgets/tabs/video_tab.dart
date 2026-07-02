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
    required this.videoPreset,
    required this.onVideoPresetChanged,
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
  final String? videoPreset;
  final void Function(String?) onVideoPresetChanged;
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

  String? get _computedVisualAR {
    if (!hasVisualCrop || mediaInfo.width == null || mediaInfo.height == null) {
      return null;
    }
    final w = (cropWidth! * mediaInfo.width!).round();
    final h = (cropHeight! * mediaInfo.height!).round();
    if (w <= 0 || h <= 0) return null;
    int gcd(int a, int b) => b == 0 ? a : gcd(b, a % b);
    final g = gcd(w, h);
    return '${w ~/ g}:${h ~/ g}';
  }

  String? get _currentAR => hasVisualCrop ? _computedVisualAR : aspectRatio;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );

    final standardAspectRatios = [
      '16:9',
      '4:3',
      '1:1',
      '9:16',
      '21:9',
      '2.39:1',
      '3:2',
      '1.85:1',
      '5:4',
    ];
    final standardResolutions = [2160, 1440, 1080, 720, 480, 360, 240];
    final swPresets = [
      'ultrafast',
      'superfast',
      'veryfast',
      'faster',
      'fast',
      'medium',
      'slow',
    ];
    final fpsOptions = [15, 24, 25, 30, 45, 60, 90, 120];

    final currentAR = _currentAR;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCard(
            title: 'Video Configuration',
            icon: Icons.videocam_outlined,
            children: [
              Text('Video Codec', style: labelStyle),
              const SizedBox(height: 8),
              // Codec Chips
              Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                children: VideoCodec.values.map((c) {
                  final isOrig = c.name == mediaInfo.videoCodec;
                  return ChoiceChip(
                    label: Text(
                      isOrig
                          ? '${c.name.toUpperCase()} (Orig)'
                          : c.name.toUpperCase(),
                    ),
                    selected: videoCodec == c,
                    onSelected: (_) => onVideoCodecChanged(c),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              const EncoderPrefInfo(),
              if (!_isVideoCopy) ...[
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Rate Control', style: labelStyle),
                ),
                const SizedBox(height: 8),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('CRF')),
                    ButtonSegment(value: false, label: Text('Bitrate')),
                  ],
                  selected: {useCrf},
                  onSelectionChanged: onUseCrfChanged,
                ),
                if (useCrf) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      SizedBox(
                        width: 56,
                        child: Text(
                          'CRF $crf',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
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
                  const SizedBox(height: 8),
                  Text('Encoder Preset (Speed)', style: labelStyle),
                  const SizedBox(height: 8),
                  // Preset Chips
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 8.0,
                    children: swPresets.map((p) {
                      return ChoiceChip(
                        label: Text(p),
                        selected: (videoPreset ?? 'fast') == p,
                        onSelected: (_) => onVideoPresetChanged(p),
                      );
                    }).toList(),
                  ),
                ] else ...[
                  const SizedBox(height: 16),
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
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Text('Aspect Ratio', style: labelStyle),
                const SizedBox(height: 8),
                // Aspect Ratio Chips
                Wrap(
                  spacing: 8.0,
                  runSpacing: 8.0,
                  children: [
                    ChoiceChip(
                      label: Text(
                        _originalAspectRatio != null
                            ? '$_originalAspectRatio (Orig)'
                            : 'Original',
                      ),
                      selected: currentAR == _originalAspectRatio,
                      onSelected: (_) =>
                          onAspectRatioChanged(_originalAspectRatio),
                    ),
                    for (final ar in standardAspectRatios)
                      if (ar != _originalAspectRatio)
                        ChoiceChip(
                          label: Text(ar),
                          selected: currentAR == ar,
                          onSelected: (_) => onAspectRatioChanged(ar),
                        ),
                    if (currentAR != null &&
                        currentAR != _originalAspectRatio &&
                        !standardAspectRatios.contains(currentAR))
                      ChoiceChip(
                        label: Text('$currentAR (Custom)'),
                        selected: true,
                        onSelected: (_) {},
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Resolution', style: labelStyle),
                const SizedBox(height: 8),
                // Resolution Chips
                Wrap(
                  spacing: 8.0,
                  runSpacing: 8.0,
                  children: [
                    ChoiceChip(
                      label: Text(
                        _originalRes != null
                            ? '${_originalRes}p (Orig)'
                            : 'Original',
                      ),
                      selected: resolution == _originalRes,
                      onSelected: (_) => onResolutionChanged(_originalRes),
                    ),
                    for (final r in standardResolutions)
                      if (r != _originalRes)
                        ChoiceChip(
                          label: Text('${r}p'),
                          selected: resolution == r,
                          onSelected: (_) => onResolutionChanged(r),
                        ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Framerate', style: labelStyle),
                const SizedBox(height: 8),
                // Framerate Chips
                Wrap(
                  spacing: 8.0,
                  runSpacing: 8.0,
                  children: [
                    ChoiceChip(
                      label: Text(
                        _originalFps != null
                            ? '$_originalFps fps (Orig)'
                            : 'Original',
                      ),
                      selected: framerate == _originalFps,
                      onSelected: (_) => onFramerateChanged(_originalFps),
                    ),
                    for (final f in fpsOptions)
                      if (f != _originalFps)
                        ChoiceChip(
                          label: Text('$f fps'),
                          selected: framerate == f,
                          onSelected: (_) => onFramerateChanged(f),
                        ),
                  ],
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
