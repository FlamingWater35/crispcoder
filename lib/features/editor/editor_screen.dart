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
import '../../providers/app_settings_provider.dart';
import '../../providers/preset_provider.dart';
import '../../providers/queue_provider.dart';
import '../preview/preview_screen.dart';
import 'widgets/editor_action_bar.dart';
import 'widgets/editor_error_view.dart';
import 'widgets/encoder_pref_info.dart';
import 'widgets/media_info_card.dart';
import 'widgets/section_card.dart';
import 'widgets/source_picker.dart';

/// Source + advanced configuration screen. Validates inputs before enqueue.
/// Encoder preference is sourced from global app settings, not per-encode.
class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key});

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  final _formKey = GlobalKey<FormState>();

  String? _sourcePath;
  MediaInfo? _mediaInfo;
  bool _probing = false;
  String? _error;

  // Preset & Advanced Configuration State
  String? _selectedPresetId = 'custom';
  VideoCodec _videoCodec = VideoCodec.h264;
  bool _useCrf = true;
  int _crf = 23;
  int _videoBitrate = 4000; // kbps
  String _resolution = '1920x1080';
  int? _framerate = 30;
  AudioCodec _audioCodec = AudioCodec.aac;
  int _audioBitrate = 160; // kbps
  ContainerFormat _container = ContainerFormat.mp4;
  bool _faststart = true;

  // Editing State
  bool _removeAudio = false;
  int? _burnSubtitleIndex;
  final _startController = TextEditingController();
  final _endController = TextEditingController();

  bool get _isVideoCopy => _videoCodec == VideoCodec.copy;
  bool get _isAudioCopy => _audioCodec == AudioCodec.copy;

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

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

  /// Maps a probed container format string to the nearest enum value.
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

  /// Applies source media properties to the state for the "Custom" preset.
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

    // Reset editing state
    _removeAudio = false;
    _burnSubtitleIndex = null;
    _startController.clear();
    _endController.clear();
  }

  /// Applies a selected preset's properties to the editor state.
  void _applyPreset(TranscodePreset preset) {
    _videoCodec = preset.videoCodec;
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

    // Apply editing state from preset
    _removeAudio = preset.removeAudio;
    _burnSubtitleIndex = preset.burnSubtitleIndex;
    _startController.text = preset.startTime ?? '';
    _endController.text = preset.endTime ?? '';
  }

  /// Validates time format to ensure FFmpeg receives proper HH:MM:SS input.
  String? _validateTime(String? value) {
    if (value == null || value.isEmpty) return null;
    final regex = RegExp(r'^(\d{1,2}):([0-5]\d):([0-5]\d)$');
    if (!regex.hasMatch(value)) {
      return 'Use HH:MM:SS format';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final presets = ref.watch(presetProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('New Encode')),
      body: _error != null
          ? EditorErrorView(message: _error!, onRetry: _clearError)
          : SafeArea(
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SourcePicker(
                              path: _sourcePath,
                              probing: _probing,
                              onPick: _pickSource,
                            ),
                            if (_mediaInfo != null) ...[
                              const SizedBox(height: 16),
                              MediaInfoCard(info: _mediaInfo!),
                              const SizedBox(height: 16),
                              SectionCard(
                                title: 'Preset',
                                icon: Icons.tune_rounded,
                                children: [_buildPresetDropdown(presets)],
                              ),
                              const SizedBox(height: 16),
                              SectionCard(
                                title: 'Editing & Subtitles',
                                icon: Icons.content_cut_rounded,
                                children: _buildEditingChildren(),
                              ),
                              const SizedBox(height: 16),
                              SectionCard(
                                title: 'Video',
                                icon: Icons.videocam_outlined,
                                children: _buildVideoChildren(),
                              ),
                              const SizedBox(height: 16),
                              SectionCard(
                                title: 'Audio',
                                icon: Icons.graphic_eq_outlined,
                                children: _buildAudioChildren(),
                              ),
                              const SizedBox(height: 16),
                              SectionCard(
                                title: 'Container',
                                icon: Icons.folder_outlined,
                                children: _buildContainerChildren(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    EditorActionBar(
                      canSubmit: _canSubmit,
                      hasSource: _sourcePath != null,
                      onPreview: _openPreview,
                      onSubmit: _submit,
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  /// Preset selector dropdown: "Custom (Match Source)" or a saved preset.
  Widget _buildPresetDropdown(List<TranscodePreset> presets) {
    return DropdownButtonFormField<String>(
      decoration: const InputDecoration(
        labelText: 'Preset',
        border: OutlineInputBorder(),
      ),
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
    );
  }

  /// Builds the editing & subtitles form fields.
  List<Widget> _buildEditingChildren() {
    return [
      SwitchListTile(
        title: const Text('Remove Audio'),
        subtitle: const Text('Strip the audio track from the output'),
        value: _removeAudio,
        onChanged: (v) => setState(() => _removeAudio = v),
        contentPadding: EdgeInsets.zero,
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: _startController,
              validator: _validateTime,
              decoration: const InputDecoration(
                labelText: 'Start Time',
                hintText: '00:00:00',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.play_arrow, size: 20),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: _endController,
              validator: _validateTime,
              decoration: const InputDecoration(
                labelText: 'End Time',
                hintText: '00:00:00',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.stop, size: 20),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<int?>(
        decoration: const InputDecoration(
          labelText: 'Hardcode Subtitles (Burn-in)',
          border: OutlineInputBorder(),
        ),
        initialValue: _burnSubtitleIndex,
        items: [
          const DropdownMenuItem(value: null, child: Text('None')),
          for (final sub in _mediaInfo?.subtitleTracks ?? <SubtitleTrack>[])
            DropdownMenuItem(value: sub.index, child: Text(sub.label)),
        ],
        onChanged: (v) => setState(() => _burnSubtitleIndex = v),
      ),
    ];
  }

  /// Builds the video settings form fields, conditional on codec selection.
  List<Widget> _buildVideoChildren() {
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

    return [
      DropdownButtonFormField<VideoCodec>(
        decoration: const InputDecoration(
          labelText: 'Video Codec',
          border: OutlineInputBorder(),
        ),
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
      const SizedBox(height: 8),
      const EncoderPrefInfo(),
      if (!_isVideoCopy) ...[
        const SizedBox(height: 12),
        // Rate control segmented selector
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
          selected: {_useCrf},
          onSelectionChanged: (selection) =>
              setState(() => _useCrf = selection.first),
        ),
        if (_useCrf) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                width: 56,
                child: Text(
                  'CRF $_crf',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
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
          ),
        ] else ...[
          const SizedBox(height: 12),
          TextFormField(
            decoration: const InputDecoration(
              labelText: 'Video Bitrate (kbps)',
              border: OutlineInputBorder(),
            ),
            initialValue: _videoBitrate.toString(),
            keyboardType: TextInputType.number,
            onChanged: (v) => _videoBitrate = int.tryParse(v) ?? 4000,
          ),
        ],
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          decoration: const InputDecoration(
            labelText: 'Resolution',
            border: OutlineInputBorder(),
          ),
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
          decoration: const InputDecoration(
            labelText: 'Framerate',
            border: OutlineInputBorder(),
          ),
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
    ];
  }

  /// Builds the audio settings form fields, conditional on codec and remove-audio.
  List<Widget> _buildAudioChildren() {
    final standardAudioBitrates = [320, 256, 192, 160, 128, 96];
    final audioBitrateOptions = [...standardAudioBitrates];
    if (_originalAudioBitrate != null &&
        !audioBitrateOptions.contains(_originalAudioBitrate)) {
      audioBitrateOptions.add(_originalAudioBitrate!);
    }

    return [
      DropdownButtonFormField<AudioCodec>(
        decoration: const InputDecoration(
          labelText: 'Audio Codec',
          border: OutlineInputBorder(),
        ),
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
      if (!_isAudioCopy && !_removeAudio) ...[
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          decoration: const InputDecoration(
            labelText: 'Audio Bitrate',
            border: OutlineInputBorder(),
          ),
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
    ];
  }

  /// Builds the container format selection and faststart toggle.
  List<Widget> _buildContainerChildren() {
    final originalContainer = _mapContainer(_mediaInfo?.container);

    return [
      DropdownButtonFormField<ContainerFormat>(
        decoration: const InputDecoration(
          labelText: 'Format',
          border: OutlineInputBorder(),
        ),
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
          subtitle: const Text('Move moov atom to file start for streaming'),
          value: _faststart,
          onChanged: (v) => setState(() => _faststart = v),
          contentPadding: EdgeInsets.zero,
        ),
    ];
  }

  bool get _canSubmit => _sourcePath != null && !_probing;

  /// Opens the file picker, requests permissions, and probes the selected file.
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

  /// Opens the source preview player in a new route.
  void _openPreview() {
    if (_sourcePath == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PreviewScreen(path: _sourcePath!)),
    );
  }

  /// Builds the encode task from current state and enqueues it.
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final sourcePath = _sourcePath;
    if (sourcePath == null) return;

    final settings = ref.read(appSettingsProvider);
    final encoderPref = settings.encoderPreference;

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
      audioBitrate: _isAudioCopy || _removeAudio ? 0 : _audioBitrate,
      container: _container,
      encoderPref: encoderPref,
      faststart: _faststart,
      twoPass: false,
      isBuiltIn: false,
      removeAudio: _removeAudio,
      burnSubtitleIndex: _burnSubtitleIndex,
      startTime: _startController.text.isEmpty ? null : _startController.text,
      endTime: _endController.text.isEmpty ? null : _endController.text,
    );

    final baseName = PathHelpers.sanitizeFileName(
      p.basenameWithoutExtension(sourcePath),
    );

    // Use custom output directory from settings if available, else fallback to source dir
    final outDir = settings.outputDirectory ?? p.dirname(sourcePath);

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
      Navigator.of(context).pop();
    }
  }

  void _clearError() => setState(() => _error = null);
}
