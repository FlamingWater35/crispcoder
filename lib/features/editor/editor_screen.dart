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
import '../preview/preview_models.dart';
import '../preview/preview_screen.dart';
import 'widgets/editor_action_bar.dart';
import 'widgets/editor_error_view.dart';
import 'widgets/media_info_card.dart';
import 'widgets/source_picker.dart';
import 'widgets/tabs/audio_tab.dart';
import 'widgets/tabs/output_tab.dart';
import 'widgets/tabs/quick_edit_tab.dart';
import 'widgets/tabs/video_tab.dart';

/// Source selection + advanced configuration screen. Validates all inputs
/// before enqueueing a task. Uses a tabbed layout to separate basic and
/// advanced configurations for a cleaner UX.
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
  OutputType _outputType = OutputType.video;
  VideoCodec _videoCodec = VideoCodec.h264;
  bool _useCrf = true;
  int _crf = 23;
  int _videoBitrate = 4000;
  String? _videoPreset = 'fast'; // Default software encoder preset
  int? _resolution; // Height in pixels (e.g., 1080)
  String? _aspectRatio; // String representation like "16:9"

  // Visual Crop State
  double? _cropLeft;
  double? _cropTop;
  double? _cropWidth;
  double? _cropHeight;

  int? _framerate = 30;
  AudioCodec _audioCodec = AudioCodec.aac;
  int _audioBitrate = 160;
  ContainerFormat _container = ContainerFormat.mp4;
  bool _faststart = true;

  // Editing State
  bool _removeAudio = false;
  int? _burnSubtitleIndex;
  final _startController = TextEditingController();
  final _endController = TextEditingController();

  bool get _isVideoCopy => _videoCodec == VideoCodec.copy;
  bool get _isAudioCopy => _audioCodec == AudioCodec.copy;
  bool get _hasVisualCrop => _cropWidth != null && _cropWidth! < 1.0;

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  Duration? _parseTimeToDuration(String? value) {
    if (value == null || value.isEmpty) return null;
    final regex = RegExp(r'^(\d{1,2}):([0-5]\d):([0-5]\d)$');
    final match = regex.firstMatch(value);
    if (match == null) return null;
    return Duration(
      hours: int.parse(match.group(1)!),
      minutes: int.parse(match.group(2)!),
      seconds: int.parse(match.group(3)!),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }

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

    _resolution = _mediaInfo?.height;

    final w = _mediaInfo?.width;
    final h = _mediaInfo?.height;
    if (w != null && h != null && w > 0 && h > 0) {
      int gcd(int a, int b) => b == 0 ? a : gcd(b, a % b);
      final g = gcd(w, h);
      _aspectRatio = '${w ~/ g}:${h ~/ g}';
    } else {
      _aspectRatio = null;
    }

    _framerate = _mediaInfo?.frameRate?.round() ?? 30;
    _audioBitrate = _mediaInfo?.audioBitrateBitsPerSec != null
        ? _mediaInfo!.audioBitrateBitsPerSec! ~/ 1000
        : 160;
    _container = _mapContainer(_mediaInfo!.container);
    _useCrf = true;
    _crf = 23;
    _videoPreset = 'fast';

    _removeAudio = false;
    _burnSubtitleIndex = null;
    _startController.clear();
    if (_mediaInfo!.duration != null) {
      _endController.text = _formatDuration(_mediaInfo!.duration!);
    } else {
      _endController.clear();
    }

    _cropLeft = null;
    _cropTop = null;
    _cropWidth = null;
    _cropHeight = null;
  }

  void _applyPreset(TranscodePreset preset) {
    _outputType = preset.outputType;
    _videoCodec = preset.videoCodec;
    _useCrf = preset.crf != null;
    _crf = preset.crf ?? 23;
    _videoBitrate = preset.videoBitrate ?? 4000;
    _videoPreset = preset.videoPreset ?? 'fast';
    _resolution = preset.resolution ?? _mediaInfo?.height;
    _aspectRatio = preset.aspectRatio;
    _framerate = preset.framerate ?? _mediaInfo?.frameRate?.round() ?? 30;
    _audioCodec = preset.audioCodec;
    _audioBitrate = preset.audioBitrate > 0
        ? preset.audioBitrate
        : (_mediaInfo?.audioBitrateBitsPerSec != null
              ? _mediaInfo!.audioBitrateBitsPerSec! ~/ 1000
              : 160);
    _container = preset.container;
    _faststart = preset.faststart;

    _removeAudio = preset.removeAudio;
    _burnSubtitleIndex = preset.burnSubtitleIndex;
    _startController.text = preset.startTime ?? '';
    _endController.text = preset.endTime ?? '';

    _cropLeft = preset.cropLeft;
    _cropTop = preset.cropTop;
    _cropWidth = preset.cropWidth;
    _cropHeight = preset.cropHeight;
  }

  @override
  Widget build(BuildContext context) {
    final presets = ref.watch(presetProvider);

    String title = 'New Encode';
    if (_mediaInfo != null) {
      title = switch (_outputType) {
        OutputType.video => 'Encode Video',
        OutputType.audio => 'Extract Audio',
        OutputType.subtitle => 'Extract Subtitles',
      };
    }

    return PopScope(
      canPop: !_probing,
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: _error != null
            ? EditorErrorView(message: _error!, onRetry: _clearError)
            : SafeArea(
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      if (_mediaInfo != null) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: MediaInfoCard(info: _mediaInfo!),
                        ),
                        // Only build tabs if mediaInfo is available
                        Expanded(child: _buildTabs(presets)),
                      ] else ...[
                        // Empty state: Show mode selector and source picker
                        Expanded(
                          child: Center(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(24.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildModeSelector(),
                                  const SizedBox(height: 32),
                                  SourcePicker(
                                    path: _sourcePath,
                                    probing: _probing,
                                    onPick: _pickSource,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
        bottomNavigationBar: EditorActionBar(
          canSubmit: _canSubmit,
          hasSource: _sourcePath != null,
          onPreview: _openPreview,
          onSubmit: _submit,
        ),
      ),
    );
  }

  /// Constructs the TabBar and TabBarView based on the selected OutputType.
  /// Guaranteed to be called only when _mediaInfo is non-null.
  Widget _buildTabs(List<TranscodePreset> presets) {
    final mediaInfo = _mediaInfo!;
    final tabs = <Tab>[];
    final tabViews = <Widget>[];

    if (_outputType == OutputType.video) {
      tabs.addAll([
        const Tab(text: 'Quick Edit'),
        const Tab(text: 'Video'),
        const Tab(text: 'Audio'),
        const Tab(text: 'Output'),
      ]);
      tabViews.addAll([
        QuickEditTab(
          presets: presets,
          selectedPresetId: _selectedPresetId,
          onPresetChanged: (v) {
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
          outputType: _outputType,
          startController: _startController,
          endController: _endController,
          sourcePath: _sourcePath,
          removeAudio: _removeAudio,
          onRemoveAudioChanged: (v) => setState(() => _removeAudio = v),
          subtitleTracks: mediaInfo.subtitleTracks,
          burnSubtitleIndex: _burnSubtitleIndex,
          onSubtitleChanged: (v) => setState(() => _burnSubtitleIndex = v),
          onTrimPreview: _openTrimPreview,
        ),
        VideoTab(
          mediaInfo: mediaInfo,
          videoCodec: _videoCodec,
          onVideoCodecChanged: (v) => setState(() => _videoCodec = v!),
          useCrf: _useCrf,
          onUseCrfChanged: (selection) =>
              setState(() => _useCrf = selection.first),
          crf: _crf,
          onCrfChanged: (v) => setState(() => _crf = v.toInt()),
          videoBitrate: _videoBitrate,
          onVideoBitrateChanged: (v) => _videoBitrate = int.tryParse(v) ?? 4000,
          videoPreset: _videoPreset,
          onVideoPresetChanged: (v) => setState(() => _videoPreset = v),
          hasVisualCrop: _hasVisualCrop,
          cropWidth: _cropWidth,
          cropHeight: _cropHeight,
          onCropEditor: _sourcePath != null ? _openCropEditor : null,
          aspectRatio: _aspectRatio,
          onAspectRatioChanged: (v) => setState(() {
            _aspectRatio = v;
            _cropLeft = null;
            _cropTop = null;
            _cropWidth = null;
            _cropHeight = null;
          }),
          resolution: _resolution,
          onResolutionChanged: (v) => setState(() => _resolution = v),
          framerate: _framerate,
          onFramerateChanged: (v) => setState(() => _framerate = v),
        ),
        AudioTab(
          mediaInfo: mediaInfo,
          audioCodec: _audioCodec,
          onAudioCodecChanged: (v) => setState(() => _audioCodec = v!),
          audioBitrate: _audioBitrate,
          onAudioBitrateChanged: (v) => setState(() => _audioBitrate = v!),
          isAudioCopy: _isAudioCopy,
          removeAudio: _removeAudio,
        ),
        OutputTab(
          mediaInfo: mediaInfo,
          container: _container,
          onContainerChanged: (v) {
            setState(() {
              _container = v!;
              _faststart = v == ContainerFormat.mp4;
            });
          },
          faststart: _faststart,
          onFaststartChanged: (v) => setState(() => _faststart = v),
        ),
      ]);
    } else if (_outputType == OutputType.audio) {
      tabs.addAll([const Tab(text: 'Quick Edit'), const Tab(text: 'Audio')]);
      tabViews.addAll([
        QuickEditTab(
          presets: presets,
          selectedPresetId: _selectedPresetId,
          onPresetChanged: (v) {
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
          outputType: _outputType,
          startController: _startController,
          endController: _endController,
          sourcePath: _sourcePath,
          removeAudio: _removeAudio,
          onRemoveAudioChanged: (v) => setState(() => _removeAudio = v),
          subtitleTracks: mediaInfo.subtitleTracks,
          burnSubtitleIndex: _burnSubtitleIndex,
          onSubtitleChanged: (v) => setState(() => _burnSubtitleIndex = v),
          onTrimPreview: _openTrimPreview,
        ),
        AudioTab(
          mediaInfo: mediaInfo,
          audioCodec: _audioCodec,
          onAudioCodecChanged: (v) => setState(() => _audioCodec = v!),
          audioBitrate: _audioBitrate,
          onAudioBitrateChanged: (v) => setState(() => _audioBitrate = v!),
          isAudioCopy: _isAudioCopy,
          removeAudio: _removeAudio,
        ),
      ]);
    } else if (_outputType == OutputType.subtitle) {
      tabs.add(const Tab(text: 'Subtitles'));
      tabViews.add(
        QuickEditTab(
          presets: presets,
          selectedPresetId: _selectedPresetId,
          onPresetChanged: (v) {
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
          outputType: _outputType,
          startController: _startController,
          endController: _endController,
          sourcePath: _sourcePath,
          removeAudio: _removeAudio,
          onRemoveAudioChanged: (v) => setState(() => _removeAudio = v),
          subtitleTracks: mediaInfo.subtitleTracks,
          burnSubtitleIndex: _burnSubtitleIndex,
          onSubtitleChanged: (v) => setState(() => _burnSubtitleIndex = v),
          onTrimPreview: _openTrimPreview,
        ),
      );
    }

    return DefaultTabController(
      length: tabs.length,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: tabs,
          ),
          Expanded(child: TabBarView(children: tabViews)),
        ],
      ),
    );
  }

  /// Extracts the SegmentedButton for OutputType selection. Only visible on the initial screen.
  Widget _buildModeSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Select Output Mode',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          SegmentedButton<OutputType>(
            segments: const [
              ButtonSegment(
                value: OutputType.video,
                label: Text('Video'),
                icon: Icon(Icons.movie),
              ),
              ButtonSegment(
                value: OutputType.audio,
                label: Text('Audio'),
                icon: Icon(Icons.music_note),
              ),
              ButtonSegment(
                value: OutputType.subtitle,
                label: Text('Subtitles'),
                icon: Icon(Icons.subtitles),
              ),
            ],
            selected: {_outputType},
            onSelectionChanged: (selection) {
              setState(() {
                _outputType = selection.first;
                if (_outputType != OutputType.video) {
                  _removeAudio = false;
                }
              });
            },
          ),
        ],
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

  Future<void> _openTrimPreview() async {
    if (_sourcePath == null) return;

    final duration = _mediaInfo?.duration;
    final result = await Navigator.of(context).push<TrimResult>(
      MaterialPageRoute(
        builder: (_) => PreviewScreen(
          path: _sourcePath!,
          trimMode: true,
          initialStart: _parseTimeToDuration(_startController.text),
          initialEnd: _parseTimeToDuration(_endController.text) ?? duration,
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _startController.text = _formatDuration(result.start);
        _endController.text = _formatDuration(result.end);
      });
    }
  }

  Future<void> _openCropEditor() async {
    if (_sourcePath == null) return;

    final initialCrop = _hasVisualCrop
        ? CropResult(_cropLeft!, _cropTop!, _cropWidth!, _cropHeight!)
        : null;

    final result = await Navigator.of(context).push<CropResult>(
      MaterialPageRoute(
        builder: (_) => PreviewScreen(
          path: _sourcePath!,
          cropMode: true,
          initialCrop: initialCrop,
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _cropLeft = result.left;
        _cropTop = result.top;
        _cropWidth = result.width;
        _cropHeight = result.height;
        _aspectRatio = null;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final sourcePath = _sourcePath;
    if (sourcePath == null) return;

    // Subtitle extraction validation
    if (_outputType == OutputType.subtitle && _burnSubtitleIndex == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a subtitle track to extract.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final startDur = _parseTimeToDuration(_startController.text);
    final endDur = _parseTimeToDuration(_endController.text);
    if (startDur != null && endDur != null && startDur >= endDur) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Start time must be before end time.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final settings = ref.read(appSettingsProvider);
    final encoderPref = settings.encoderPreference;

    final preset = TranscodePreset(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: 'Custom Encode',
      category: 'Custom',
      outputType: _outputType,
      videoCodec: _videoCodec,
      crf: !_isVideoCopy && _useCrf ? _crf : null,
      videoBitrate: !_isVideoCopy && !_useCrf ? _videoBitrate : null,
      videoPreset: !_isVideoCopy && _useCrf ? _videoPreset : null,
      resolution: _isVideoCopy ? null : _resolution,
      aspectRatio: _isVideoCopy || _hasVisualCrop ? null : _aspectRatio,
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
      cropLeft: _isVideoCopy ? null : _cropLeft,
      cropTop: _isVideoCopy ? null : _cropTop,
      cropWidth: _isVideoCopy ? null : _cropWidth,
      cropHeight: _isVideoCopy ? null : _cropHeight,
    );

    final baseName = PathHelpers.sanitizeFileName(
      p.basenameWithoutExtension(sourcePath),
    );

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
