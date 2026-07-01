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
import 'widgets/encoder_pref_info.dart';
import 'widgets/media_info_card.dart';
import 'widgets/section_card.dart';
import 'widgets/source_picker.dart';

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
  VideoCodec _videoCodec = VideoCodec.h264;
  bool _useCrf = true;
  int _crf = 23;
  int _videoBitrate = 4000;
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

  int? get _originalRes => _mediaInfo?.height;

  /// Computes the simplified fraction string of the source aspect ratio
  String? get _originalAspectRatio {
    final w = _mediaInfo?.width;
    final h = _mediaInfo?.height;
    if (w == null || h == null || w == 0 || h == 0) return null;
    int gcd(int a, int b) => b == 0 ? a : gcd(b, a % b);
    final g = gcd(w, h);
    return '${w ~/ g}:${h ~/ g}';
  }

  int? get _originalFps => _mediaInfo?.frameRate?.round();
  int? get _originalAudioBitrate => _mediaInfo?.audioBitrateBitsPerSec != null
      ? _mediaInfo!.audioBitrateBitsPerSec! ~/ 1000
      : null;

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

    _resolution = _originalRes;
    _aspectRatio = _originalAspectRatio;
    _framerate = _originalFps ?? 30;
    _audioBitrate = _originalAudioBitrate ?? 160;
    _container = _mapContainer(_mediaInfo!.container);
    _useCrf = true;
    _crf = 23;

    _removeAudio = false;
    _burnSubtitleIndex = null;
    _startController.clear();
    if (_mediaInfo!.duration != null) {
      _endController.text = _formatDuration(_mediaInfo!.duration!);
    } else {
      _endController.clear();
    }

    // Reset Visual Crop
    _cropLeft = null;
    _cropTop = null;
    _cropWidth = null;
    _cropHeight = null;
  }

  void _applyPreset(TranscodePreset preset) {
    _videoCodec = preset.videoCodec;
    _useCrf = preset.crf != null;
    _crf = preset.crf ?? 23;
    _videoBitrate = preset.videoBitrate ?? 4000;
    _resolution = preset.resolution ?? _originalRes;
    _aspectRatio = preset.aspectRatio ?? _originalAspectRatio;
    _framerate = preset.framerate ?? _originalFps ?? 30;
    _audioCodec = preset.audioCodec;
    _audioBitrate = preset.audioBitrate > 0
        ? preset.audioBitrate
        : (_originalAudioBitrate ?? 160);
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

    return PopScope(
      canPop: !_probing,
      child: Scaffold(
        appBar: AppBar(title: const Text('New Encode')),
        body: _error != null
            ? EditorErrorView(message: _error!, onRetry: _clearError)
            : SafeArea(
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      // Pinned Source Picker and Media Info
                      if (_mediaInfo != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: MediaInfoCard(info: _mediaInfo!),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: SourcePicker(
                            path: _sourcePath,
                            probing: _probing,
                            onPick: _pickSource,
                          ),
                        ),

                      // Tabbed Configuration Area
                      if (_mediaInfo != null)
                        Expanded(
                          child: DefaultTabController(
                            length: 4,
                            child: Column(
                              children: [
                                const TabBar(
                                  isScrollable: true,
                                  tabAlignment: TabAlignment.start,
                                  tabs: [
                                    Tab(text: 'Quick Edit'),
                                    Tab(text: 'Video'),
                                    Tab(text: 'Audio'),
                                    Tab(text: 'Output'),
                                  ],
                                ),
                                Expanded(
                                  child: TabBarView(
                                    children: [
                                      _buildQuickEditTab(presets),
                                      _buildVideoTab(),
                                      _buildAudioTab(),
                                      _buildOutputTab(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
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

  /// Quick Edit Tab: Presets, Trimming, Cropping, Subtitles, Remove Audio
  Widget _buildQuickEditTab(List<TranscodePreset> presets) {
    final startDur = _parseTimeToDuration(_startController.text);
    final endDur = _parseTimeToDuration(_endController.text);
    final trimDuration =
        (startDur != null && endDur != null && endDur > startDur)
        ? endDur - startDur
        : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCard(
            title: 'Preset',
            icon: Icons.tune_rounded,
            children: [_buildPresetDropdown(presets)],
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Editing & Subtitles',
            icon: Icons.content_cut_rounded,
            children: [
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
              if (trimDuration != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Trimmed length: ${_formatDuration(trimDuration)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.content_cut_rounded),
                  label: const Text('Trim Visually'),
                  onPressed: _sourcePath != null ? _openTrimPreview : null,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                decoration: const InputDecoration(
                  labelText: 'Hardcode Subtitles (Burn-in)',
                  border: OutlineInputBorder(),
                ),
                initialValue: _burnSubtitleIndex,
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('None'),
                  ),
                  for (final sub
                      in _mediaInfo?.subtitleTracks ?? <SubtitleTrack>[])
                    DropdownMenuItem<int?>(
                      value: sub.subtitleStreamIndex,
                      child: Text(sub.label),
                    ),
                ],
                onChanged: (v) => setState(() => _burnSubtitleIndex = v),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Video Tab: Codecs, Rate Control, Aspect Ratio, Resolution, Framerate
  Widget _buildVideoTab() {
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
                      _hasVisualCrop ? 'Edit Visual Crop' : 'Crop Visually',
                    ),
                    onPressed: _sourcePath != null ? _openCropEditor : null,
                  ),
                ),
                if (_hasVisualCrop)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Custom crop applied (${(_cropWidth! * 100).toStringAsFixed(0)}% x ${(_cropHeight! * 100).toStringAsFixed(0)}%)',
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
                  initialValue: _aspectRatio,
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
                  onChanged: (v) => setState(() {
                    _aspectRatio = v;
                    // Clear visual crop if using aspect ratio dropdown
                    _cropLeft = null;
                    _cropTop = null;
                    _cropWidth = null;
                    _cropHeight = null;
                  }),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                  decoration: const InputDecoration(
                    labelText: 'Resolution',
                    border: OutlineInputBorder(),
                  ),
                  initialValue: _resolution,
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
                  onChanged: (v) => setState(() => _resolution = v),
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
                    return DropdownMenuItem<int>(
                      value: f,
                      child: Text(isOrig ? '$f fps (original)' : '$f fps'),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _framerate = v),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Audio Tab: Audio Codec and Bitrate selection
  Widget _buildAudioTab() {
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
        ],
      ),
    );
  }

  /// Output Tab: Container format and Faststart optimization
  Widget _buildOutputTab() {
    final originalContainer = _mapContainer(_mediaInfo?.container);

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
              subtitle: const Text(
                'Move moov atom to file start for streaming',
              ),
              value: _faststart,
              onChanged: (v) => setState(() => _faststart = v),
              contentPadding: EdgeInsets.zero,
            ),
        ],
      ),
    );
  }

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

  /// Opens the visual crop editor and maps the result to internal state.
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
        // Clear aspect ratio string since exact crop is applied
        _aspectRatio = null;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final sourcePath = _sourcePath;
    if (sourcePath == null) return;

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
      videoCodec: _videoCodec,
      crf: !_isVideoCopy && _useCrf ? _crf : null,
      videoBitrate: !_isVideoCopy && !_useCrf ? _videoBitrate : null,
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
