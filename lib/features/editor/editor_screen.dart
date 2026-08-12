import 'dart:io';

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exceptions.dart';
import '../../core/utils/path_helpers.dart';
import '../../data/models/device_capability.dart';
import '../../data/models/encode_task.dart';
import '../../data/models/media_info.dart';
import '../../data/models/transcode_preset.dart';
import '../../data/services/gallery_service.dart';
import '../../data/services/media_probe_service.dart';
import '../../data/services/permission_service.dart';
import '../../providers/app_settings_provider.dart';
import '../../providers/device_capability_provider.dart';
import '../../providers/preset_provider.dart';
import '../../providers/queue_provider.dart';
import '../preview/preview_models.dart';
import '../preview/preview_screen.dart';
import 'widgets/editor_action_bar.dart';
import 'widgets/editor_error_view.dart';
import 'widgets/editor_welcome_view.dart';
import 'widgets/media_info_card.dart';
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

  /// Original filename reported by the file picker (keeps the real video
  /// name even when the platform returns a numeric cached path on Android).
  String? _pickedFileName;

  /// True while the platform file picker is open (between pressing the
  /// source card and a file being chosen or the picker being dismissed).
  bool _picking = false;
  String? _error;

  String? _selectedPresetId = 'custom';
  OutputType _outputType = OutputType.video;
  VideoCodec _videoCodec = VideoCodec.h264;
  bool _useCrf = true;
  int _crf = 23;
  int _videoBitrate = 4000;
  String? _videoPreset = 'fast';
  int? _resolution;
  String? _aspectRatio;

  double? _cropLeft;
  double? _cropTop;
  double? _cropWidth;
  double? _cropHeight;

  int? _framerate; // null = preserve source framerate (avoid rounding)
  AudioCodec _audioCodec = AudioCodec.aac;
  int _audioBitrate = 160;
  ContainerFormat _container = ContainerFormat.mp4;
  bool _faststart = true;
  bool _twoPass = false;

  bool _removeAudio = false;
  int? _burnSubtitleIndex;
  SubtitleFormat _subtitleFormat = SubtitleFormat.srt;
  final _startController = TextEditingController();
  final _endController = TextEditingController();

  /// User-editable output base name (without extension). Defaults to the
  /// derived source name; lets the user rename the output before enqueueing
  /// (important when the picker only exposes numeric cache names like "29").
  final _outputNameController = TextEditingController();

  bool get _isVideoCopy => _videoCodec == VideoCodec.copy;
  bool get _isAudioCopy => _audioCodec == AudioCodec.copy;
  bool get _hasVisualCrop => _cropWidth != null && _cropWidth! < 1.0;

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    _outputNameController.dispose();
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
  /// Uses detectedResolution instead of raw height so that a 1920x800
  /// source is treated as 1080p, not 800p.
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

    _resolution = _mediaInfo?.detectedResolution;

    final w = _mediaInfo?.width;
    final h = _mediaInfo?.height;
    if (w != null && h != null && w > 0 && h > 0) {
      int gcd(int a, int b) => b == 0 ? a : gcd(b, a % b);
      final g = gcd(w, h);
      _aspectRatio = '${w ~/ g}:${h ~/ g}';
    } else {
      _aspectRatio = null;
    }

    _framerate = null; // preserve source framerate (no forced CFR)
    _audioBitrate = _mediaInfo?.audioBitrateBitsPerSec != null
        ? _mediaInfo!.audioBitrateBitsPerSec! ~/ 1000
        : 160;
    _container = _mapContainer(_mediaInfo!.container);
    _useCrf = true;
    _crf = 23;
    _videoPreset = 'fast';

    _removeAudio = false;
    _burnSubtitleIndex = null;
    _subtitleFormat = SubtitleFormat.srt;
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
    _resolution = preset.resolution ?? _mediaInfo?.detectedResolution;
    _aspectRatio = preset.aspectRatio;
    // null means preserve source framerate; only built-in presets that
    // explicitly force one (e.g. Fast 1080p30) set a value here.
    _framerate = preset.framerate;
    _audioCodec = preset.audioCodec;
    _audioBitrate = preset.audioBitrate > 0
        ? preset.audioBitrate
        : (_mediaInfo?.audioBitrateBitsPerSec != null
              ? _mediaInfo!.audioBitrateBitsPerSec! ~/ 1000
              : 160);
    _container = preset.container;
    _faststart = preset.faststart;
    _twoPass = preset.twoPass;

    _removeAudio = preset.removeAudio;
    _burnSubtitleIndex = preset.burnSubtitleIndex;
    _subtitleFormat = preset.subtitleFormat;
    _startController.text = preset.startTime ?? '';
    _endController.text = preset.endTime ?? '';

    _cropLeft = preset.cropLeft;
    _cropTop = preset.cropTop;
    _cropWidth = preset.cropWidth;
    _cropHeight = preset.cropHeight;
  }

  /// Evaluates device capabilities and current settings to determine
  /// whether hardware encoding will be used, and builds a warning message
  /// if software encoding is forced due to subtitles or codec limits.
  ///
  /// [asyncCap] is supplied by the caller: `build` passes
  /// `ref.watch(deviceCapabilityProvider)` so the encoder banner rebuilds
  /// when the capability finishes loading, while `_buildPreset` (called from
  /// an event handler, not build) passes `ref.read`.
  (bool, String) _resolveEncoderStatus(AsyncValue<DeviceCapability> asyncCap) {
    final settings = ref.read(appSettingsProvider);

    // Safely get the DeviceCapability value if it has finished loading
    final cap = asyncCap.maybeWhen(data: (d) => d, orElse: () => null);

    bool wantsHw =
        settings.encoderPreference == EncoderPreference.hardware ||
        (settings.encoderPreference == EncoderPreference.auto &&
            cap?.preferHardware == true);

    final bool isSubtitleBurn =
        _burnSubtitleIndex != null && _burnSubtitleIndex! >= 0;

    if (_videoCodec == VideoCodec.h264 && cap?.supportsH264Hw != true) {
      wantsHw = false;
    }
    if (_videoCodec == VideoCodec.hevc && cap?.supportsHevcHw != true) {
      wantsHw = false;
    }
    if (_videoCodec == VideoCodec.av1 && cap?.supportsAv1Hw != true) {
      wantsHw = false;
    }
    if (_videoCodec == VideoCodec.vp9) wantsHw = false;

    String feedbackMessage = '';
    if (isSubtitleBurn) {
      wantsHw = false;
      feedbackMessage = 'Subtitle burn-in requires software encoder.';
    } else if (settings.encoderPreference == EncoderPreference.hardware &&
        !wantsHw) {
      feedbackMessage = 'Hardware unsupported for this codec. Using software.';
    } else if (settings.encoderPreference == EncoderPreference.auto &&
        !wantsHw &&
        cap?.preferHardware == true) {
      feedbackMessage = 'Hardware unsupported for this codec. Using software.';
    }

    return (wantsHw, feedbackMessage);
  }

  @override
  Widget build(BuildContext context) {
    final presets = ref.watch(presetProvider);

    // Resolve encoder status dynamically on rebuild. Watch the capability
    // provider so the banner updates once detection completes (a plain read
    // here would leave the 'hardware unsupported' hint stale).
    final (isUsingHw, encoderFeedback) = _resolveEncoderStatus(
      ref.watch(deviceCapabilityProvider),
    );

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
                      // AnimatedSwitcher slides between the welcome (no
                      // source) and the editor (source loaded) views.
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 350),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) {
                            final offset =
                                Tween<Offset>(
                                  begin: const Offset(0.08, 0),
                                  end: Offset.zero,
                                ).animate(
                                  CurvedAnimation(
                                    parent: animation,
                                    curve: Curves.easeOutCubic,
                                  ),
                                );
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: offset,
                                child: child,
                              ),
                            );
                          },
                          child: _mediaInfo != null
                              ? Column(
                                  key: const ValueKey('editor-loaded'),
                                  children: [
                                    Padding(
                                      // Extra bottom padding separates the
                                      // source file details from the editor
                                      // sections bar below.
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        16,
                                        16,
                                        14,
                                      ),
                                      child: Column(
                                        children: [
                                          MediaInfoCard(info: _mediaInfo!),
                                          const SizedBox(height: 12),
                                          // Editable output filename: defaults
                                          // to the derived source name so the
                                          // user can rename numeric cache
                                          // names ("29") before enqueueing.
                                          TextFormField(
                                            key: const ValueKey(
                                              'output-name-field',
                                            ),
                                            controller: _outputNameController,
                                            decoration: InputDecoration(
                                              labelText: 'Output name',
                                              hintText: 'My Video',
                                              helperText:
                                                  'Without extension — the '
                                                  'correct one is added '
                                                  'automatically.',
                                              border:
                                                  const OutlineInputBorder(),
                                              prefixIcon: const Icon(
                                                Icons.edit_outlined,
                                                size: 20,
                                              ),
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 10,
                                                  ),
                                            ),
                                            textInputAction:
                                                TextInputAction.next,
                                          ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      child: _buildTabs(
                                        presets,
                                        isUsingHw,
                                        encoderFeedback,
                                      ),
                                    ),
                                  ],
                                )
                              : SizedBox.expand(
                                  key: const ValueKey('editor-welcome'),
                                  child: EditorWelcomeView(
                                    outputType: _outputType,
                                    onOutputTypeChanged: (type) {
                                      setState(() {
                                        _outputType = type;
                                        if (type != OutputType.video) {
                                          _removeAudio = false;
                                        }
                                      });
                                    },
                                    probing: _probing,
                                    isPicking: _picking,
                                    onPick: _pickSource,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        // The action bar (Preview / Start Encode) only makes sense once a
        // source video is picked — hide it entirely in the initial view.
        bottomNavigationBar: _sourcePath == null
            ? null
            : EditorActionBar(
                canSubmit: _canSubmit,
                hasSource: _sourcePath != null,
                onPreview: _openPreview,
                onSubmit: _submit,
              ),
      ),
    );
  }

  Widget _buildTabs(
    List<TranscodePreset> presets,
    bool isUsingHw,
    String encoderFeedback,
  ) {
    final theme = Theme.of(context);
    final mediaInfo = _mediaInfo!;
    final tabs = <Tab>[];
    final tabViews = <Widget>[];

    // Only presets matching the current output mode are relevant. The
    // built-in presets are all video presets; offering them in audio or
    // subtitle extraction mode is confusing and applying one would silently
    // flip the mode back to video. Audio/subtitle modes fall back to
    // "Custom (Match Source)".
    final modePresets = _outputType == OutputType.video
        ? presets
        : presets
              .where((p) => p.outputType == _outputType)
              .toList();

    if (_outputType == OutputType.video) {
      tabs.addAll([
        const Tab(
          text: 'Quick Edit',
          icon: Icon(Icons.bolt_rounded, size: 18),
          height: 50,
        ),
        const Tab(
          text: 'Video',
          icon: Icon(Icons.videocam_outlined, size: 18),
          height: 50,
        ),
        const Tab(
          text: 'Audio',
          icon: Icon(Icons.music_note_outlined, size: 18),
          height: 50,
        ),
        const Tab(
          text: 'Output',
          icon: Icon(Icons.output_rounded, size: 18),
          height: 50,
        ),
      ]);
      tabViews.addAll([
        QuickEditTab(
          presets: modePresets,
          selectedPresetId: _selectedPresetId,
          onPresetChanged: (v) {
            if (v == null) return;
            setState(() {
              _selectedPresetId = v;
              if (v == 'custom') {
                _applySourceDefaults();
              } else {
                final preset = modePresets.firstWhere((p) => p.id == v);
                _applyPreset(preset);
              }
            });
          },
          outputType: _outputType,
          startController: _startController,
          endController: _endController,
          sourcePath: _sourcePath,
          isVideoCopy: _isVideoCopy,
          removeAudio: _removeAudio,
          onRemoveAudioChanged: (v) => setState(() => _removeAudio = v),
          subtitleTracks: mediaInfo.subtitleTracks,
          burnSubtitleIndex: _burnSubtitleIndex,
          onSubtitleChanged: (v) => setState(() => _burnSubtitleIndex = v),
          subtitleFormat: _subtitleFormat,
          onSubtitleFormatChanged: (v) =>
              setState(() => _subtitleFormat = v),
          onTrimPreview: _openTrimPreview,
        ),
        VideoTab(
          mediaInfo: mediaInfo,
          videoCodec: _videoCodec,
          onVideoCodecChanged: (v) => setState(() {
            _videoCodec = v!;
            // Video copy (passthrough) cannot burn subtitles — the video
            // stream is not re-encoded, so no filter can render text onto it.
            if (_videoCodec == VideoCodec.copy) {
              _burnSubtitleIndex = null;
            }
          }),
          useCrf: _useCrf,
          onUseCrfChanged: (selection) =>
              setState(() => _useCrf = selection.first),
          crf: _crf,
          onCrfChanged: (v) => setState(() => _crf = v.toInt()),
          videoBitrate: _videoBitrate,
          onVideoBitrateChanged: (v) {
            setState(() {
              _videoBitrate = int.tryParse(v) ?? 4000;
            });
          },
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
          isUsingHw: isUsingHw,
          encoderFeedback: encoderFeedback,
          twoPass: _twoPass,
          onTwoPassChanged: (v) => setState(() => _twoPass = v),
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
      tabs.addAll([
        const Tab(
          text: 'Quick Edit',
          icon: Icon(Icons.bolt_rounded, size: 18),
          height: 50,
        ),
        const Tab(
          text: 'Audio',
          icon: Icon(Icons.music_note_outlined, size: 18),
          height: 50,
        ),
      ]);
      tabViews.addAll([
        QuickEditTab(
          presets: modePresets,
          selectedPresetId: _selectedPresetId,
          onPresetChanged: (v) {
            if (v == null) return;
            setState(() {
              _selectedPresetId = v;
              if (v == 'custom') {
                _applySourceDefaults();
              } else {
                final preset = modePresets.firstWhere((p) => p.id == v);
                _applyPreset(preset);
              }
            });
          },
          outputType: _outputType,
          startController: _startController,
          endController: _endController,
          sourcePath: _sourcePath,
          isVideoCopy: _isVideoCopy,
          removeAudio: _removeAudio,
          onRemoveAudioChanged: (v) => setState(() => _removeAudio = v),
          subtitleTracks: mediaInfo.subtitleTracks,
          burnSubtitleIndex: _burnSubtitleIndex,
          onSubtitleChanged: (v) => setState(() => _burnSubtitleIndex = v),
          subtitleFormat: _subtitleFormat,
          onSubtitleFormatChanged: (v) =>
              setState(() => _subtitleFormat = v),
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
      tabs.add(
        const Tab(
          text: 'Subtitles',
          icon: Icon(Icons.subtitles_outlined, size: 18),
          height: 50,
        ),
      );
      tabViews.add(
        QuickEditTab(
          presets: modePresets,
          selectedPresetId: _selectedPresetId,
          onPresetChanged: (v) {
            if (v == null) return;
            setState(() {
              _selectedPresetId = v;
              if (v == 'custom') {
                _applySourceDefaults();
              } else {
                final preset = modePresets.firstWhere((p) => p.id == v);
                _applyPreset(preset);
              }
            });
          },
          outputType: _outputType,
          startController: _startController,
          endController: _endController,
          sourcePath: _sourcePath,
          isVideoCopy: _isVideoCopy,
          removeAudio: _removeAudio,
          onRemoveAudioChanged: (v) => setState(() => _removeAudio = v),
          subtitleTracks: mediaInfo.subtitleTracks,
          burnSubtitleIndex: _burnSubtitleIndex,
          onSubtitleChanged: (v) => setState(() => _burnSubtitleIndex = v),
          subtitleFormat: _subtitleFormat,
          onSubtitleFormatChanged: (v) =>
              setState(() => _subtitleFormat = v),
          onTrimPreview: _openTrimPreview,
        ),
      );
    }

    return DefaultTabController(
      length: tabs.length,
      child: Column(
        children: [
          // Styled tab bar: a rounded pill that hugs its content width (and
          // stays centered), or fills the row when the tabs are too wide.
          Padding(
            // Minimal vertical padding so the bar is compact.
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
            child: Align(
              alignment: Alignment.center,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.shadow.withValues(alpha: 0.05),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                // IntrinsicWidth makes the pill shrink to the TabBar's content
                // width instead of stretching full-width.
                child: IntrinsicWidth(
                  child: TabBar(
                    isScrollable: true,
                    // Centers the tabs when they fit; scrolls when overflow.
                    tabAlignment: TabAlignment.center,
                    dividerColor: Colors.transparent,
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicator: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    // Rounded focus/selection highlight.
                    splashBorderRadius: BorderRadius.circular(9),
                    labelColor: theme.colorScheme.onSecondaryContainer,
                    unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                    labelStyle: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    unselectedLabelStyle: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    tabs: tabs,
                  ),
                ),
              ),
            ),
          ),
          Expanded(child: TabBarView(children: tabViews)),
        ],
      ),
    );
  }

  bool get _canSubmit => _sourcePath != null && !_probing;

  Future<void> _pickSource() async {
    // Picking phase: the platform file picker is opening. Show "Opening file
    // picker…" until a file is chosen (or the picker is dismissed).
    setState(() {
      _picking = true;
      _probing = false;
      _error = null;
    });
    try {
      await ref.read(permissionServiceProvider).requireMediaRead();

      String? name;
      String? path;
      if (ref.read(appSettingsProvider).useFilePickerPackage) {
        // Legacy path: the original simple file_picker implementation.
        final result = await FilePicker.pickFile(type: FileType.video);
        name = result?.name;
        path = result?.path;
      } else {
        // Default: native SAF picker with DISPLAY_NAME filename detection.
        try {
          final picked = await ref.read(galleryServiceProvider).pickVideo();
          name = picked?.name;
          path = picked?.path;
        } on MissingPluginException {
          // Stale build without the native channel — fall back.
          final result = await FilePicker.pickFile(type: FileType.video);
          name = result?.name;
          path = result?.path;
        } on PlatformException {
          // Native picker failed (provider error) — fall back instead of
          // stranding the user.
          final result = await FilePicker.pickFile(type: FileType.video);
          name = result?.name;
          path = result?.path;
        }
      }

      if (path == null) {
        setState(() => _picking = false);
        return;
      }

      // A file was picked — now read/analyze it. (Local copy so the value
      // stays non-null inside the setState closure below.)
      final resolvedPath = path;
      setState(() {
        _picking = false;
        _probing = true;
      });
      final info = await ref.read(mediaProbeServiceProvider).probe(resolvedPath);
      setState(() {
        _sourcePath = resolvedPath;
        _mediaInfo = info;
        _selectedPresetId = 'custom';
        _applySourceDefaults();
        // Keep the picked name on the field so _submit derives sourceName
        // from it (previously dead code — always null, which degraded the
        // file_picker fallback to video_<timestamp> names).
        _pickedFileName = name;
        // Default the editable output name to the derived display name
        // (picker name, or path basename, or timestamped fallback).
        _outputNameController.text = PathHelpers.safeOutputBaseName(
          PathHelpers.deriveDisplayName(pickerName: name, path: resolvedPath),
        );
        _probing = false;
      });
    } on AppException catch (e) {
      setState(() {
        _error = e.userMessage;
        _picking = false;
        _probing = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not load source video.';
        _picking = false;
        _probing = false;
      });
    }
  }

  void _openPreview() {
    if (_sourcePath == null) return;
    // Preview subtitle extraction converts a stream to SRT — pass the first
    // TEXT-based subtitle track (bitmap PGS/DVD streams cannot be converted
    // and would make preview silently show no subtitles).
    final textSubtitleIndex = _mediaInfo?.subtitleTracks
        .where((t) => t.isTextSubtitle)
        .map((t) => t.subtitleStreamIndex)
        .firstOrNull;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PreviewScreen(
          path: _sourcePath!,
          subtitleStreamIndex: textSubtitleIndex,
        ),
      ),
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

  /// Builds the [TranscodePreset] from the current editor state.
  TranscodePreset _buildPreset() {
    // Re-evaluate encoder status for submission to ensure consistency.
    // Called from an event handler (not build), so a plain read is correct.
    final (isUsingHw, _) = _resolveEncoderStatus(
      ref.read(deviceCapabilityProvider),
    );

    // CRF is only valid for software encoding. If HW is used, force bitrate mode.
    final effectiveUseCrf = !isUsingHw && _useCrf;

    return TranscodePreset(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: 'Custom Encode',
      category: 'Custom',
      outputType: _outputType,
      videoCodec: _videoCodec,
      crf: !_isVideoCopy && effectiveUseCrf ? _crf : null,
      videoBitrate: !_isVideoCopy && !effectiveUseCrf ? _videoBitrate : null,
      videoPreset: !_isVideoCopy && effectiveUseCrf ? _videoPreset : null,
      resolution: _isVideoCopy ? null : _resolution,
      aspectRatio: _isVideoCopy || _hasVisualCrop ? null : _aspectRatio,
      framerate: _isVideoCopy ? null : _framerate,
      audioCodec: _audioCodec,
      audioBitrate: _isAudioCopy || _removeAudio ? 0 : _audioBitrate,
      container: _container,
      encoderPref: _resolveEncoderPref(),
      faststart: _faststart,
      twoPass: _twoPass,
      isBuiltIn: false,
      removeAudio: _removeAudio,
      burnSubtitleIndex: _burnSubtitleIndex,
      subtitleFormat: _subtitleFormat,
      startTime: _startController.text.isEmpty ? null : _startController.text,
      endTime: _endController.text.isEmpty ? null : _endController.text,
      cropLeft: _isVideoCopy ? null : _cropLeft,
      cropTop: _isVideoCopy ? null : _cropTop,
      cropWidth: _isVideoCopy ? null : _cropWidth,
      cropHeight: _isVideoCopy ? null : _cropHeight,
      // Captured at enqueue time so audio-copy output extension and
      // WebM/MP4 copy-mode validation can inspect the actual source codec.
      sourceAudioCodec: _mediaInfo?.audioCodec,
      sourceVideoCodec: _mediaInfo?.videoCodec,
    );
  }

  EncoderPreference _resolveEncoderPref() {
    return ref.read(appSettingsProvider).encoderPreference;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final sourcePath = _sourcePath;
    if (sourcePath == null) return;

    if (_outputType == OutputType.subtitle && _burnSubtitleIndex == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a subtitle track to extract.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Subtitle extraction only works for text-based tracks. Image-based
    // subtitles (PGS/DVD/VobSub) cannot be converted to SRT/ASS by FFmpeg —
    // block them up front with a clear message instead of failing silently.
    if (_outputType == OutputType.subtitle) {
      final track = _mediaInfo?.subtitleTracks.firstWhereOrNull(
        (t) => t.subtitleStreamIndex == _burnSubtitleIndex,
      );
      if (track != null && !track.isTextSubtitle) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This subtitle track is image-based and cannot be converted '
              'to SRT/ASS. Choose a text subtitle track.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
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

    // Validate codec/container compatibility up front so the user is told
    // about invalid combinations (e.g. WebM + H.264) instead of getting a
    // broken file from FFmpeg. The preset is built once and reused, so the
    // compatibility check and the enqueued task describe the same config.
    final preset = _buildPreset();
    final issues = preset.compatibilityIssues();
    if (issues.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(issues.map((i) => i.message).join('\n')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final settings = ref.read(appSettingsProvider);

    // Retain a user-facing source name: the picker's PlatformFile name when
    // it looks real, otherwise the path basename — and if both are bare
    // numbers (Android file_picker cache copies like "29"), a readable
    // timestamped name. The queue UI, notifications and history show this
    // name, never the raw numeric cache path.
    final sourceFileName = PathHelpers.deriveDisplayName(
      pickerName: _pickedFileName,
      path: sourcePath,
    );

    // Output base name: the user-editable field wins; otherwise fall back to
    // the derived display name. Never empty or a bare number.
    final requestedName = _outputNameController.text.trim().isEmpty
        ? sourceFileName
        : _outputNameController.text.trim();
    final baseName = PathHelpers.safeOutputBaseName(requestedName);

    // Output directory: a custom directory wins for ALL output types (video,
    // audio, and subtitle outputs all land there). Without one, video stays
    // next to the source (and is inserted into the device gallery), while
    // audio/subtitle outputs go to a dedicated app-documents folder — never
    // into the volatile file_picker cache or the video gallery. Ensure the
    // directory exists before encoding so FFmpeg can create the file.
    final outDir = await PathHelpers.resolveOutputDirectory(
      outputType: preset.outputType,
      customDirectory: settings.outputDirectory,
      sourcePath: sourcePath,
    );
    await Directory(outDir).create(recursive: true);

    final outputPath = PathHelpers.uniqueOutputPath(
      directory: outDir,
      baseName: '${baseName}_encoded',
      extension: preset.fileExtension,
    );

    final task = EncodeTask(
      id: 'task_${DateTime.now().millisecondsSinceEpoch}',
      sourcePath: sourcePath,
      sourceName: sourceFileName,
      outputPath: outputPath,
      preset: preset,
      createdAt: DateTime.now(),
      totalDurationSeconds:
          (_mediaInfo?.duration?.inMilliseconds ?? 0) / 1000.0,
      // Captured so the hardware-encoder path and GOP calculation can use the
      // real source rate instead of assuming 30 fps.
      sourceFrameRate: _mediaInfo?.frameRate,
    );

    await ref.read(queueProvider.notifier).enqueue(task);

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _clearError() => setState(() => _error = null);
}
