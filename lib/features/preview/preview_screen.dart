import 'dart:io';

import 'package:chewie/chewie.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import 'preview_models.dart';
import 'widgets/crop_overlay.dart';
import 'widgets/trim_bar.dart';

/// Video preview screen with optional real-time trimming and visual cropping.
class PreviewScreen extends StatefulWidget {
  const PreviewScreen({
    super.key,
    required this.path,
    this.trimMode = false,
    this.cropMode = false,
    this.initialStart,
    this.initialEnd,
    this.initialCrop,
  });

  final String path;
  final bool trimMode;
  final bool cropMode;
  final Duration? initialStart;
  final Duration? initialEnd;
  final CropResult? initialCrop;

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  bool _loading = true;
  String? _error;

  // Trim state
  double _startFraction = 0.0;
  double _endFraction = 1.0;
  Duration _totalDuration = Duration.zero;
  bool? _wasPlaying;
  DateTime? _lastSeekTime;
  static const _seekThrottle = Duration(milliseconds: 60);

  // Crop state
  Rect _cropRect = const Rect.fromLTWH(0.0, 0.0, 1.0, 1.0);
  double? _aspectConstraint; // Null = free, 1.0 = square, 16/9 = widescreen

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  /// Opens the file, initialises the controller, and applies mode setups.
  Future<void> _initPlayer() async {
    try {
      final file = File(widget.path);
      if (!await file.exists()) {
        throw FileSystemException('File not found', widget.path);
      }

      final controller = VideoPlayerController.file(file);
      await controller.initialize();

      _totalDuration = controller.value.duration;
      if (_totalDuration.inMilliseconds <= 0) {
        throw const FileSystemException(
          'Video duration could not be determined.',
        );
      }

      controller.addListener(_onVideoUpdate);

      if (widget.trimMode) {
        if (widget.initialStart != null) {
          _startFraction = _toFraction(widget.initialStart!);
        }
        if (widget.initialEnd != null) {
          _endFraction = _toFraction(widget.initialEnd!);
        }
        _enforceMinGap();

        await controller.setLooping(false);
        await controller.seekTo(startDuration);
        await controller.play();
      } else if (widget.cropMode) {
        if (widget.initialCrop != null) {
          _cropRect = Rect.fromLTWH(
            widget.initialCrop!.left,
            widget.initialCrop!.top,
            widget.initialCrop!.width,
            widget.initialCrop!.height,
          );
        }
        await controller.setLooping(true);
        await controller.play();
      } else {
        final subsList = await _extractSubtitles(widget.path);

        _chewieController = ChewieController(
          videoPlayerController: controller,
          autoPlay: true,
          looping: false,
          showControls: true,
          showSubtitles: subsList.isNotEmpty,
          subtitle: Subtitles(subsList),
          subtitleBuilder: (context, text) {
            final isLandscape =
                MediaQuery.of(context).size.width >
                MediaQuery.of(context).size.height;
            final bottomPadding = isLandscape ? 20.0 : 120.0;

            return Padding(
              padding: EdgeInsets.only(bottom: bottomPadding),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          },
          errorBuilder: (ctx, msg) => Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Playback error: $msg', textAlign: TextAlign.center),
            ),
          ),
        );
      }

      if (mounted) {
        setState(() {
          _videoController = controller;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error =
              'Could not open preview. The file may be corrupted or '
              'in an unsupported format.';
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _videoController?.removeListener(_onVideoUpdate);
    _chewieController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  Future<List<Subtitle>> _extractSubtitles(String path) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final srtPath =
          '${tempDir.path}/sub_${DateTime.now().millisecondsSinceEpoch}.srt';

      final session = await FFmpegKit.execute(
        '-i "$path" -map 0:s:0 -c:s srt "$srtPath"',
      );
      final rc = await session.getReturnCode();

      if (ReturnCode.isSuccess(rc)) {
        final file = File(srtPath);
        if (await file.exists()) {
          final srtContent = await file.readAsString();
          await file.delete();

          if (srtContent.trim().isEmpty) return [];
          return _parseSrt(srtContent);
        }
      }
    } catch (_) {}
    return [];
  }

  String _cleanSubtitleText(String text) {
    var cleaned = text.replaceAll(RegExp(r'\{[^}]*\}'), '');
    cleaned = cleaned.replaceAll(RegExp(r'<[^>]*>'), '');
    cleaned = cleaned
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#39;', "'");
    return cleaned.trim();
  }

  List<Subtitle> _parseSrt(String srt) {
    final lines = srt.split('\n');
    final subtitles = <Subtitle>[];
    int i = 0;

    while (i < lines.length) {
      if (lines[i].trim().isEmpty) {
        i++;
        continue;
      }
      i++;
      if (i >= lines.length) break;

      final timeMatch = RegExp(
        r'(\d{2}:\d{2}:\d{2},\d{3})\s-->\s(\d{2}:\d{2}:\d{2},\d{3})',
      ).firstMatch(lines[i]);

      if (timeMatch == null) break;
      final start = _parseSrtTime(timeMatch.group(1)!);
      final end = _parseSrtTime(timeMatch.group(2)!);
      i++;

      final textLines = <String>[];
      while (i < lines.length && lines[i].trim().isNotEmpty) {
        textLines.add(_cleanSubtitleText(lines[i]));
        i++;
      }

      final text = textLines.where((l) => l.isNotEmpty).join('\n');
      if (text.isEmpty) continue;

      subtitles.add(
        Subtitle(start: start, end: end, text: text, index: subtitles.length),
      );
    }
    return subtitles;
  }

  Duration _parseSrtTime(String t) {
    final parts = t.split(':');
    final secsParts = parts[2].split(',');
    return Duration(
      hours: int.parse(parts[0]),
      minutes: int.parse(parts[1]),
      seconds: int.parse(secsParts[0]),
      milliseconds: int.parse(secsParts[1]),
    );
  }

  double _toFraction(Duration d) {
    final ms = _totalDuration.inMilliseconds;
    if (ms <= 0) return 0.0;
    return (d.inMilliseconds / ms).clamp(0.0, 1.0);
  }

  Duration get startDuration => Duration(
    milliseconds: (_startFraction * _totalDuration.inMilliseconds).round(),
  );

  Duration get endDuration => Duration(
    milliseconds: (_endFraction * _totalDuration.inMilliseconds).round(),
  );

  void _enforceMinGap() {
    const minGap = 0.01;
    if (_startFraction >= _endFraction) {
      _startFraction = (_endFraction - minGap).clamp(0.0, 1.0);
    }
    if (_endFraction - _startFraction < minGap) {
      _endFraction = (_startFraction + minGap).clamp(0.0, 1.0);
    }
  }

  void _throttledSeek(Duration position) {
    final now = DateTime.now();
    if (_lastSeekTime == null ||
        now.difference(_lastSeekTime!) >= _seekThrottle) {
      _lastSeekTime = now;
      _videoController?.seekTo(position);
    }
  }

  void _onVideoUpdate() {
    final c = _videoController;
    if (c == null || !c.value.isInitialized) return;

    // Confine playback to the trim region while playing
    if (widget.trimMode && c.value.isPlaying) {
      final pos = c.value.position;
      if (pos >= endDuration || pos < startDuration) {
        c.seekTo(startDuration);
      }
    }

    // Rebuild only when play/pause icon needs to change
    final isPlaying = c.value.isPlaying;
    if (isPlaying != _wasPlaying) {
      _wasPlaying = isPlaying;
      if (mounted) setState(() {});
    }
  }

  void _onStartChanged(double fraction) {
    _videoController?.pause();
    setState(() {
      _startFraction = fraction.clamp(0.0, _endFraction - 0.01);
    });
    _throttledSeek(startDuration);
  }

  void _onEndChanged(double fraction) {
    _videoController?.pause();
    setState(() {
      _endFraction = fraction.clamp(_startFraction + 0.01, 1.0);
    });
    _throttledSeek(endDuration);
  }

  void _onScrub(double fraction) {
    final clamped = fraction.clamp(
      widget.trimMode ? _startFraction : 0.0,
      widget.trimMode ? _endFraction : 1.0,
    );
    final pos = Duration(
      milliseconds: (clamped * _totalDuration.inMilliseconds).round(),
    );
    _videoController?.seekTo(pos);
    setState(() {});
  }

  void _togglePlayPause() {
    final c = _videoController;
    if (c == null) return;

    if (c.value.isPlaying) {
      c.pause();
      return;
    }

    final start = widget.trimMode ? startDuration : Duration.zero;
    final end = widget.trimMode ? endDuration : _totalDuration;
    if (c.value.position >= end || c.value.position < start) {
      c.seekTo(start);
    }
    c.play();
  }

  void _resetTrim() {
    _videoController?.pause();
    setState(() {
      _startFraction = 0.0;
      _endFraction = 1.0;
    });
    _videoController?.seekTo(Duration.zero);
  }

  void _saveTrim() {
    Navigator.of(context).pop(TrimResult(startDuration, endDuration));
  }

  void _resetCrop() {
    setState(() {
      _aspectConstraint = null;
      _cropRect = const Rect.fromLTWH(0.0, 0.0, 1.0, 1.0);
    });
  }

  void _centerCrop() {
    setState(() {
      // Center the crop rect based on its current dimensions
      double newLeft = ((1.0 - _cropRect.width) / 2).clamp(
        0.0,
        1.0 - _cropRect.width,
      );
      double newTop = ((1.0 - _cropRect.height) / 2).clamp(
        0.0,
        1.0 - _cropRect.height,
      );
      _cropRect = Rect.fromLTWH(
        newLeft,
        newTop,
        _cropRect.width,
        _cropRect.height,
      );
    });
  }

  void _saveCrop() {
    Navigator.of(context).pop(
      CropResult(
        _cropRect.left,
        _cropRect.top,
        _cropRect.width,
        _cropRect.height,
      ),
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    String title = 'Preview';
    if (widget.trimMode) title = 'Trim Video';
    if (widget.cropMode) title = 'Crop Video';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (widget.trimMode || widget.cropMode)
            TextButton(
              onPressed: widget.trimMode ? _saveTrim : _saveCrop,
              child: const Text('Save'),
            ),
        ],
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null || _videoController == null) {
      return _buildError();
    }

    if (!widget.trimMode && !widget.cropMode) {
      if (_chewieController == null) return _buildError();
      return Chewie(controller: _chewieController!);
    }

    return Column(
      children: [
        Expanded(child: _buildVideoArea()),
        // Show playback controls in both Trim and Crop modes
        if (widget.trimMode || widget.cropMode) _buildControls(),
        if (widget.cropMode) _buildCropControls(),
      ],
    );
  }

  Widget _buildError() {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(
              _error ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoArea() {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: RepaintBoundary(
        child: AspectRatio(
          aspectRatio: _videoController!.value.aspectRatio,
          child: widget.cropMode
              ? CropOverlay(
                  controller: _videoController!,
                  cropRect: _cropRect,
                  aspectConstraint: _aspectConstraint,
                  onCropChanged: (newRect) {
                    setState(() => _cropRect = newRect);
                  },
                )
              : VideoPlayer(_videoController!),
        ),
      ),
    );
  }

  Widget _buildControls() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _fmt(widget.trimMode ? startDuration : Duration.zero),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (widget.trimMode)
                Text(
                  'Trim Region',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else
                const SizedBox(width: 48),
              Text(
                _fmt(widget.trimMode ? endDuration : _totalDuration),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          RepaintBoundary(
            child: TrimBar(
              controller: _videoController!,
              totalDuration: _totalDuration,
              startFraction: _startFraction,
              endFraction: _endFraction,
              trimMode: widget.trimMode,
              onStartChanged: _onStartChanged,
              onEndChanged: _onEndChanged,
              onScrub: _onScrub,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.trimMode)
                IconButton(
                  tooltip: 'Reset trim',
                  icon: const Icon(Icons.refresh),
                  onPressed: _resetTrim,
                )
              else
                const SizedBox(width: 48),
              const SizedBox(width: 16),
              IconButton.filled(
                icon: Icon(
                  _videoController!.value.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
                iconSize: 32,
                onPressed: _togglePlayPause,
              ),
              const SizedBox(width: 16),
              if (widget.trimMode)
                IconButton(
                  tooltip: 'Save trim',
                  icon: const Icon(Icons.check_rounded),
                  onPressed: _saveTrim,
                )
              else
                const SizedBox(width: 48),
            ],
          ),
        ],
      ),
    );
  }

  /// Bottom control panel for the Crop Mode.
  Widget _buildCropControls() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant, width: 1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Aspect Ratio',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _buildAspectChip('Free', null),
              _buildAspectChip('1:1', 1.0),
              _buildAspectChip('4:3', 4 / 3),
              _buildAspectChip('3:2', 3 / 2),
              _buildAspectChip('16:9', 16 / 9),
              _buildAspectChip('9:16', 9 / 16),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Reset crop',
                icon: const Icon(Icons.crop_free_rounded),
                onPressed: _resetCrop,
              ),
              const SizedBox(width: 24),
              IconButton(
                tooltip: 'Center crop',
                icon: const Icon(Icons.center_focus_strong_rounded),
                onPressed: _centerCrop,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Pill button for selecting an aspect ratio constraint.
  Widget _buildAspectChip(String label, double? ratio) {
    final isSelected = _aspectConstraint == ratio;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {
        setState(() {
          _aspectConstraint = ratio;
          // Re-center crop while maintaining size or aspect ratio
          if (ratio != null) {
            double newWidth = _cropRect.width;
            double newHeight = newWidth / ratio;
            if (newHeight > 1.0) {
              newHeight = 1.0;
              newWidth = newHeight * ratio;
            }
            double newLeft = 0.5 - (newWidth / 2);
            double newTop = 0.5 - (newHeight / 2);
            _cropRect = Rect.fromLTWH(newLeft, newTop, newWidth, newHeight);
          }
        });
      },
    );
  }
}
