import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/errors/app_exceptions.dart';
import '../../core/utils/path_helpers.dart';
import '../../data/models/encode_task.dart';
import '../../data/models/media_info.dart';
import '../../data/models/transcode_preset.dart';
import '../../data/services/media_probe_service.dart';
import '../../data/services/permission_service.dart';
import '../../providers/preset_provider.dart';
import '../../providers/queue_provider.dart';
import '../preview/preview_screen.dart';

/// Source + advanced configuration screen. Validates inputs before enqueue.
class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key});

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  String? _sourcePath;
  MediaInfo? _mediaInfo;
  bool _probing = false;
  String? _error;

  // Preset & Advanced Configuration State
  String? _selectedPresetId = 'custom';
  VideoCodec _videoCodec = VideoCodec.h264;
  EncoderPreference _encoderPref = EncoderPreference.auto;
  bool _useCrf = true;
  int _crf = 23;
  int _videoBitrate = 4000; // kbps
  String _resolution = '1920x1080';
  int? _framerate = 30;
  AudioCodec _audioCodec = AudioCodec.aac;
  int _audioBitrate = 160; // kbps
  ContainerFormat _container = ContainerFormat.mp4;
  bool _faststart = true;

  bool get _isVideoCopy => _videoCodec == VideoCodec.copy;
  bool get _isAudioCopy => _audioCodec == AudioCodec.copy;

  // Helpers to identify original source values for dynamic UI labeling
  String get _originalRes {
    if (_mediaInfo?.width != null && _mediaInfo?.height != null) {
      return '${_mediaInfo!.width}x${_mediaInfo!.height}';
    }
    return '';
  }

  int? get _originalFps => _mediaInfo?.frameRate?.round();
  int? get _originalAudioBitrate => _mediaInfo?.audioBitrateBitsPerSec != null
      ? _mediaInfo!.audioBitrateBitsPerSec! ~/ 1000
      : null;

  ContainerFormat _mapContainer(String? format) {
    if (format == null) return ContainerFormat.mp4;
    if (format.contains('mp4') || format.contains('mov'))
      return ContainerFormat.mp4;
    if (format.contains('matroska') || format.contains('mkv'))
      return ContainerFormat.mkv;
    if (format.contains('webm')) return ContainerFormat.webm;
    return ContainerFormat.mp4;
  }

  /// Applies source media properties to the state for the "Custom" preset
  void _applySourceDefaults() {
    if (_mediaInfo == null) return;

    _videoCodec = VideoCodec.values.firstWhere(
      (c) => c.name == _mediaInfo!.videoCodec,
      orElse: () => VideoCodec.h264,
    );
    _audioCodec = AudioCodec.values.firstWhere(
      (c) => c.name == _mediaInfo!.audioCodec,
      orElse: () => AudioCodec.aac,
    );

    _resolution = _originalRes.isNotEmpty ? _originalRes : '1920x1080';
    _framerate = _originalFps ?? 30;
    _audioBitrate = _originalAudioBitrate ?? 160;
    _container = _mapContainer(_mediaInfo!.container);
    _useCrf = true;
    _crf = 23;
  }

  /// Applies a selected preset's properties to the state
  void _applyPreset(TranscodePreset preset) {
    _videoCodec = preset.videoCodec;
    _encoderPref = preset.encoderPref;
    _useCrf = preset.crf != null;
    _crf = preset.crf ?? 23;
    _videoBitrate = preset.videoBitrate ?? 4000;
    _resolution =
        preset.resolution ??
        (_originalRes.isNotEmpty ? _originalRes : '1920x1080');
    _framerate = preset.framerate ?? _originalFps ?? 30;
    _audioCodec = preset.audioCodec;
    _audioBitrate = preset.audioBitrate > 0
        ? preset.audioBitrate
        : (_originalAudioBitrate ?? 160);
    _container = preset.container;
    _faststart = preset.faststart;
  }

  @override
  Widget build(BuildContext context) {
    final presets = ref.watch(presetProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('New Encode')),
      body: _error != null
          ? _ErrorView(message: _error!, onRetry: _clearError)
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SourcePicker(
                    path: _sourcePath,
                    probing: _probing,
                    onPick: _pickSource,
                  ),
                  if (_mediaInfo != null) ...[
                    const SizedBox(height: 12),
                    _MediaInfoCard(info: _mediaInfo!),
                    const SizedBox(height: 24),
                    _buildAdvancedOptions(presets),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('Preview'),
                            onPressed: _openPreview,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            icon: const Icon(Icons.queue),
                            label: const Text('Start Encode'),
                            onPressed: _canSubmit ? _submit : null,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  /// Builds the dynamic form fields for advanced transcoding settings
  Widget _buildAdvancedOptions(List<TranscodePreset> presets) {
    final standardResolutions = ['1920x1080', '1280x720', '854x480', '640x360'];
    final resOptions = [...standardResolutions];
    if (_originalRes.isNotEmpty && !resOptions.contains(_originalRes)) {
      resOptions.add(_originalRes);
    }

    final standardFps = [24, 25, 30, 60];
    final fpsOptions = [...standardFps];
    if (_originalFps != null && !fpsOptions.contains(_originalFps)) {
      fpsOptions.add(_originalFps!);
    }

    final standardAudioBitrates = [320, 256, 192, 160, 128, 96];
    final audioBitrateOptions = [...standardAudioBitrates];
    if (_originalAudioBitrate != null &&
        !audioBitrateOptions.contains(_originalAudioBitrate)) {
      audioBitrateOptions.add(_originalAudioBitrate!);
    }

    final originalContainer = _mapContainer(_mediaInfo?.container);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Preset'),
              initialValue: _selectedPresetId,
              items: [
                const DropdownMenuItem(
                  value: 'custom',
                  child: Text('Custom (Match Source)'),
                ),
                for (final p in presets)
                  DropdownMenuItem(value: p.id, child: Text(p.name)),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _selectedPresetId = v;
                  if (v == 'custom') {
                    _applySourceDefaults();
                  } else {
                    final preset = presets.firstWhere((p) => p.id == v);
                    _applyPreset(preset);
                  }
                });
              },
            ),
            const Divider(height: 32),

            Text(
              'Video Settings',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<VideoCodec>(
              decoration: const InputDecoration(labelText: 'Video Codec'),
              initialValue: _videoCodec,
              items: VideoCodec.values.map((c) {
                final isOrig = c.name == _mediaInfo?.videoCodec;
                return DropdownMenuItem(
                  value: c,
                  child: Text(
                    isOrig
                        ? '${c.name.toUpperCase()} (original)'
                        : c.name.toUpperCase(),
                  ),
                );
              }).toList(),
              onChanged: (v) => setState(() => _videoCodec = v!),
            ),
            const SizedBox(height: 12),
            if (!_isVideoCopy) ...[
              DropdownButtonFormField<EncoderPreference>(
                decoration: const InputDecoration(labelText: 'Encoder'),
                initialValue: _encoderPref,
                items: EncoderPreference.values
                    .map(
                      (e) => DropdownMenuItem(
                        value: e,
                        child: Text(e.name.toUpperCase()),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _encoderPref = v!),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Rate Control:'),
                  const SizedBox(width: 12),
                  ToggleButtons(
                    isSelected: [_useCrf, !_useCrf],
                    onPressed: (index) => setState(() => _useCrf = index == 0),
                    children: const [Text('CRF'), Text('Bitrate')],
                  ),
                ],
              ),
              if (_useCrf)
                Row(
                  children: [
                    Text('CRF: $_crf'),
                    Expanded(
                      child: Slider(
                        value: _crf.toDouble(),
                        min: 0,
                        max: 51,
                        divisions: 51,
                        label: _crf.toString(),
                        onChanged: (v) => setState(() => _crf = v.toInt()),
                      ),
                    ),
                  ],
                )
              else
                TextFormField(
                  decoration: const InputDecoration(
                    labelText: 'Video Bitrate (kbps)',
                  ),
                  initialValue: _videoBitrate.toString(),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => _videoBitrate = int.tryParse(v) ?? 4000,
                ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Resolution'),
                initialValue: _resolution,
                items: resOptions.map((r) {
                  final isOrig = r == _originalRes;
                  return DropdownMenuItem(
                    value: r,
                    child: Text(isOrig ? '$r (original)' : r),
                  );
                }).toList(),
                onChanged: (v) => setState(() => _resolution = v!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                decoration: const InputDecoration(labelText: 'Framerate'),
                initialValue: _framerate,
                items: fpsOptions.map((f) {
                  final isOrig = f == _originalFps;
                  return DropdownMenuItem(
                    value: f,
                    child: Text(isOrig ? '$f fps (original)' : '$f fps'),
                  );
                }).toList(),
                onChanged: (v) => setState(() => _framerate = v),
              ),
            ],
            const Divider(height: 32),

            Text(
              'Audio Settings',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<AudioCodec>(
              decoration: const InputDecoration(labelText: 'Audio Codec'),
              initialValue: _audioCodec,
              items: AudioCodec.values.map((c) {
                final isOrig = c.name == _mediaInfo?.audioCodec;
                return DropdownMenuItem(
                  value: c,
                  child: Text(
                    isOrig
                        ? '${c.name.toUpperCase()} (original)'
                        : c.name.toUpperCase(),
                  ),
                );
              }).toList(),
              onChanged: (v) => setState(() => _audioCodec = v!),
            ),
            if (!_isAudioCopy) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                decoration: const InputDecoration(labelText: 'Audio Bitrate'),
                initialValue: _audioBitrate,
                items: audioBitrateOptions.map((b) {
                  final isOrig = b == _originalAudioBitrate;
                  return DropdownMenuItem(
                    value: b,
                    child: Text(isOrig ? '$b kbps (original)' : '$b kbps'),
                  );
                }).toList(),
                onChanged: (v) => setState(() => _audioBitrate = v!),
              ),
            ],
            const Divider(height: 32),

            Text(
              'Container Settings',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ContainerFormat>(
              decoration: const InputDecoration(labelText: 'Format'),
              initialValue: _container,
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
              onChanged: (v) {
                setState(() {
                  _container = v!;
                  _faststart = v == ContainerFormat.mp4;
                });
              },
            ),
            if (_container == ContainerFormat.mp4)
              SwitchListTile(
                title: const Text('Faststart (Web Optimized)'),
                value: _faststart,
                onChanged: (v) => setState(() => _faststart = v),
                contentPadding: EdgeInsets.zero,
              ),
          ],
        ),
      ),
    );
  }

  bool get _canSubmit => _sourcePath != null && !_probing;

  Future<void> _pickSource() async {
    setState(() {
      _probing = true;
      _error = null;
    });
    try {
      await ref.read(permissionServiceProvider).requireMediaRead();

      final result = await FilePicker.pickFile(type: FileType.video);

      if (result == null) {
        setState(() => _probing = false);
        return;
      }

      final path = result.path;
      if (path == null) {
        setState(() {
          _error = 'Could not retrieve file path.';
          _probing = false;
        });
        return;
      }

      final info = await ref.read(mediaProbeServiceProvider).probe(path);
      setState(() {
        _sourcePath = path;
        _mediaInfo = info;
        _selectedPresetId = 'custom';
        _applySourceDefaults();
        _probing = false;
      });
    } on AppException catch (e) {
      setState(() {
        _error = e.userMessage;
        _probing = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not load source video.';
        _probing = false;
      });
    }
  }

  void _openPreview() {
    if (_sourcePath == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PreviewScreen(path: _sourcePath!)),
    );
  }

  Future<void> _submit() async {
    final sourcePath = _sourcePath;
    if (sourcePath == null) return;

    final preset = TranscodePreset(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: 'Custom Encode',
      category: 'Custom',
      videoCodec: _videoCodec,
      crf: !_isVideoCopy && _useCrf ? _crf : null,
      videoBitrate: !_isVideoCopy && !_useCrf ? _videoBitrate : null,
      resolution: _isVideoCopy ? null : _resolution,
      framerate: _isVideoCopy ? null : _framerate,
      audioCodec: _audioCodec,
      audioBitrate: _isAudioCopy ? 0 : _audioBitrate,
      container: _container,
      encoderPref: _encoderPref,
      faststart: _faststart,
      twoPass: false,
      isBuiltIn: false,
    );

    final baseName = PathHelpers.sanitizeFileName(
      p.basenameWithoutExtension(sourcePath),
    );
    final outDir = p.dirname(sourcePath);
    final outputPath = PathHelpers.uniqueOutputPath(
      directory: outDir,
      baseName: '${baseName}_crispcoder',
      extension: preset.fileExtension,
    );

    final task = EncodeTask(
      id: 'task_${DateTime.now().millisecondsSinceEpoch}',
      sourcePath: sourcePath,
      sourceName: p.basename(sourcePath),
      outputPath: outputPath,
      preset: preset,
      createdAt: DateTime.now(),
      totalDurationSeconds: _mediaInfo?.duration?.inSeconds.toDouble() ?? 0,
    );

    await ref.read(queueProvider.notifier).enqueue(task);

    if (mounted) {
      // Simply pop back to the previous screen (the queue)
      Navigator.of(context).pop();
    }
  }

  void _clearError() => setState(() => _error = null);
}

/// Source video selector: opens the platform file picker (SAF on Android).
class _SourcePicker extends StatelessWidget {
  const _SourcePicker({
    required this.path,
    required this.probing,
    required this.onPick,
  });

  final String? path;
  final bool probing;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: probing ? null : onPick,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              probing
                  ? Icons.hourglass_top
                  : (path == null ? Icons.folder_open : Icons.video_file),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                probing
                    ? 'Reading source…'
                    : (path == null
                          ? 'Tap to select a source video'
                          : path!.split('/').last),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Read-only metadata summary card shown after probing the source.
class _MediaInfoCard extends StatelessWidget {
  const _MediaInfoCard({required this.info});
  final MediaInfo info;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('Resolution', info.resolutionLabel),
      ('Duration', info.durationLabel),
      ('Video codec', info.videoCodec ?? '—'),
      ('Audio codec', info.audioCodec ?? '—'),
      ('Container', info.container ?? '—'),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            for (final (k, v) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(k, style: Theme.of(context).textTheme.bodySmall),
                    Text(v, style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Inline error UI replacing the editor body when a hard error occurs.
class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Dismiss')),
          ],
        ),
      ),
    );
  }
}
