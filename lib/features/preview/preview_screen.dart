import 'dart:io';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Trim selection returned when the user saves in trim mode.
class TrimResult {
  final Duration start;
  final Duration end;

  const TrimResult(this.start, this.end);
}

/// Video preview screen with optional real-time trimming.
///
/// In standard mode, it uses Chewie for a familiar, fully-featured video
/// player experience. In [trimMode], it bypasses Chewie for a custom
/// progress bar with two draggable handles to set start/end points.
class PreviewScreen extends StatefulWidget {
  const PreviewScreen({
    super.key,
    required this.path,
    this.trimMode = false,
    this.initialStart,
    this.initialEnd,
  });

  final String path;
  final bool trimMode;
  final Duration? initialStart;
  final Duration? initialEnd;

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  bool _loading = true;
  String? _error;

  /// Trim bounds expressed as fractions of total duration (0.0–1.0).
  double _startFraction = 0.0;
  double _endFraction = 1.0;
  Duration _totalDuration = Duration.zero;

  /// Previous playing state — used to rebuild only on play/pause change.
  bool? _wasPlaying;

  /// Throttle guard preventing rapid seeks from overwhelming the player.
  DateTime? _lastSeekTime;
  static const _seekThrottle = Duration(milliseconds: 60);

  // ---------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  /// Opens the file, initialises the controller, and applies either the
  /// standard Chewie wrapper or the custom trim listener depending on mode.
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

      if (widget.trimMode) {
        // Trim Mode Setup
        if (widget.initialStart != null) {
          _startFraction = _toFraction(widget.initialStart!);
        }
        if (widget.initialEnd != null) {
          _endFraction = _toFraction(widget.initialEnd!);
        }
        _enforceMinGap();

        controller.addListener(_onVideoUpdate);
        await controller.setLooping(false); // looping handled manually
        await controller.seekTo(startDuration);
        await controller.play();
      } else {
        // Standard Preview Setup (Chewie)
        _chewieController = ChewieController(
          videoPlayerController: controller,
          autoPlay: true,
          looping: false,
          showControls: true,
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

  // ---------------------------------------------------------------
  // Trim helpers
  // ---------------------------------------------------------------

  /// Converts a [Duration] to a 0–1 fraction of the total duration.
  double _toFraction(Duration d) {
    final ms = _totalDuration.inMilliseconds;
    if (ms <= 0) return 0.0;
    return (d.inMilliseconds / ms).clamp(0.0, 1.0);
  }

  /// Current trim start as an absolute [Duration].
  Duration get startDuration => Duration(
    milliseconds: (_startFraction * _totalDuration.inMilliseconds).round(),
  );

  /// Current trim end as an absolute [Duration].
  Duration get endDuration => Duration(
    milliseconds: (_endFraction * _totalDuration.inMilliseconds).round(),
  );

  /// Ensures at least 1 % of the video separates start and end, fixing
  /// any inverted or overlapping bounds.
  void _enforceMinGap() {
    const minGap = 0.01;
    if (_startFraction >= _endFraction) {
      _startFraction = (_endFraction - minGap).clamp(0.0, 1.0);
    }
    if (_endFraction - _startFraction < minGap) {
      _endFraction = (_startFraction + minGap).clamp(0.0, 1.0);
    }
  }

  /// Seeks to [position] at most once per [_seekThrottle] to avoid
  /// overwhelming the platform video player during rapid handle drags.
  void _throttledSeek(Duration position) {
    final now = DateTime.now();
    if (_lastSeekTime == null ||
        now.difference(_lastSeekTime!) >= _seekThrottle) {
      _lastSeekTime = now;
      _videoController?.seekTo(position);
    }
  }

  // ---------------------------------------------------------------
  // Video listener (Trim Mode Only)
  // ---------------------------------------------------------------

  /// Called on every controller update (position change, state change).
  /// In trim mode, loops playback within the selection. Triggers a widget
  /// rebuild only when the play/pause state actually changes.
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

  // ---------------------------------------------------------------
  // Gesture callbacks (Trim Mode Only)
  // ---------------------------------------------------------------

  /// Updates the start handle position, pauses playback, and seeks to the
  /// new frame so the user can see what they're trimming to.
  void _onStartChanged(double fraction) {
    _videoController?.pause();
    setState(() {
      _startFraction = fraction.clamp(0.0, _endFraction - 0.01);
    });
    _throttledSeek(startDuration);
  }

  /// Updates the end handle position, pauses playback, and seeks to the
  /// new frame.
  void _onEndChanged(double fraction) {
    _videoController?.pause();
    setState(() {
      _endFraction = fraction.clamp(_startFraction + 0.01, 1.0);
    });
    _throttledSeek(endDuration);
  }

  /// Seeks to [fraction] of the total duration. In trim mode the position
  /// is clamped to the active trim region.
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

  // ---------------------------------------------------------------
  // Transport (Trim Mode Only)
  // ---------------------------------------------------------------

  /// Toggles play/pause. When resuming from the end of the region, the
  /// playhead jumps back to the start so playback continues seamlessly.
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

  /// Resets both handles to the full video bounds.
  void _resetTrim() {
    _videoController?.pause();
    setState(() {
      _startFraction = 0.0;
      _endFraction = 1.0;
    });
    _videoController?.seekTo(Duration.zero);
  }

  /// Returns the current trim selection and closes the screen.
  void _saveTrim() {
    Navigator.of(context).pop(TrimResult(startDuration, endDuration));
  }

  // ---------------------------------------------------------------
  // Formatting
  // ---------------------------------------------------------------

  /// Formats a [Duration] as HH:MM:SS.
  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }

  // ---------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.trimMode ? 'Trim Video' : 'Preview'),
        actions: [
          if (widget.trimMode)
            TextButton(onPressed: _saveTrim, child: const Text('Save')),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null || _videoController == null) {
      return _buildError();
    }

    // Standard mode: defer entirely to Chewie's own UI and controls
    if (!widget.trimMode) {
      if (_chewieController == null) return _buildError();
      return Chewie(controller: _chewieController!);
    }

    // Trim mode: custom layered UI
    return Column(
      children: [
        Expanded(child: _buildVideoArea()),
        _buildControls(),
      ],
    );
  }

  /// Error fallback with a go-back button.
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

  /// Centered video player preserving aspect ratio with black background.
  /// Wrapped in [RepaintBoundary] so frame repaints don't cascade upward.
  Widget _buildVideoArea() {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: RepaintBoundary(
        child: AspectRatio(
          aspectRatio: _videoController!.value.aspectRatio,
          child: VideoPlayer(_videoController!),
        ),
      ),
    );
  }

  /// Bottom control panel: time labels, trim/seek bar, transport buttons.
  Widget _buildControls() {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Container(
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
            // Time labels: start (or 00:00:00) and end (or full duration)
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
            // Interactive trim / seek bar (isolated for repaint perf)
            RepaintBoundary(
              child: _TrimBar(
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
            // Transport controls
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
                // Play/pause button — icon reflects current state
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
      ),
    );
  }
}

/// Interactive progress bar with optional trim handles.
///
/// Uses [AnimatedBuilder] on the video controller so only the bar repaints
/// on position changes — the rest of the screen is unaffected. In trim mode
/// two draggable handles appear at the selection boundaries; in preview mode
/// a simple seek bar is shown.
class _TrimBar extends StatelessWidget {
  const _TrimBar({
    required this.controller,
    required this.totalDuration,
    required this.startFraction,
    required this.endFraction,
    required this.trimMode,
    required this.onStartChanged,
    required this.onEndChanged,
    required this.onScrub,
  });

  final VideoPlayerController controller;
  final Duration totalDuration;
  final double startFraction;
  final double endFraction;
  final bool trimMode;

  /// Called with an absolute 0–1 fraction when the start handle moves.
  final ValueChanged<double> onStartChanged;

  /// Called with an absolute 0–1 fraction when the end handle moves.
  final ValueChanged<double> onEndChanged;

  /// Called with an absolute 0–1 fraction when the user taps or drags the
  /// bar background to scrub the playhead.
  final ValueChanged<double> onScrub;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return SizedBox(
          height: 40,
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final pos = controller.value.position;
              final playhead = totalDuration.inMilliseconds > 0
                  ? (pos.inMilliseconds / totalDuration.inMilliseconds).clamp(
                      0.0,
                      1.0,
                    )
                  : 0.0;
              return _buildStack(context, width, playhead);
            },
          ),
        );
      },
    );
  }

  /// Builds the layered stack: background track, selection highlight,
  /// scrub area, playhead, and (in trim mode) two drag handles.
  Widget _buildStack(BuildContext context, double width, double playhead) {
    final theme = Theme.of(context);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // --- Background track ---
        Positioned(
          top: 16,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Container(
              height: 8,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
        // --- Selection highlight (trim) or played portion (preview) ---
        Positioned(
          top: 16,
          left: trimMode ? startFraction * width : 0,
          width: (trimMode ? (endFraction - startFraction) : playhead) * width,
          child: IgnorePointer(
            child: Container(
              height: 8,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
        // --- Full-bar tap/drag scrub area ---
        // Sits above the visual layers but below the handles so handle
        // gestures take priority.  HitTestBehavior.opaque ensures taps
        // on transparent areas are still captured.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => onScrub(d.localPosition.dx / width),
            onHorizontalDragUpdate: (d) => onScrub(d.localPosition.dx / width),
            child: const ColoredBox(color: Colors.transparent),
          ),
        ),
        // --- Playhead indicator ---
        Positioned(
          left: playhead * width - 1,
          top: 8,
          child: IgnorePointer(
            child: Container(
              width: 2,
              height: 24,
              color: theme.colorScheme.error,
            ),
          ),
        ),
        // --- Start handle (trim mode only) ---
        if (trimMode)
          _buildHandle(
            context,
            left: startFraction * width,
            semanticLabel: 'Start trim handle',
            onDrag: (delta) {
              final f = (startFraction + delta / width).clamp(
                0.0,
                endFraction - 0.01,
              );
              onStartChanged(f);
            },
          ),
        // --- End handle (trim mode only) ---
        if (trimMode)
          _buildHandle(
            context,
            left: endFraction * width,
            semanticLabel: 'End trim handle',
            onDrag: (delta) {
              final f = (endFraction + delta / width).clamp(
                startFraction + 0.01,
                1.0,
              );
              onEndChanged(f);
            },
          ),
      ],
    );
  }

  /// Draggable trim handle with grip icon and accessibility label.
  /// [onDrag] receives the incremental horizontal delta in pixels.
  Widget _buildHandle(
    BuildContext context, {
    required double left,
    required String semanticLabel,
    required ValueChanged<double> onDrag,
  }) {
    final theme = Theme.of(context);
    return Positioned(
      left: left - 12,
      top: 4,
      child: Semantics(
        label: semanticLabel,
        child: GestureDetector(
          onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
          child: Container(
            width: 24,
            height: 32,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.drag_handle_rounded,
              size: 16,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
