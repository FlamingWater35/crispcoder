import 'dart:async';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/errors/app_exceptions.dart';
import '../../core/utils/format_parsers.dart';
import '../../core/utils/path_helpers.dart';
import '../../main.dart';
import '../models/device_capability.dart';
import '../models/encode_progress.dart';
import '../models/encode_task.dart';
import '../models/transcode_preset.dart';
import 'media_probe_service.dart';

/// Encapsulates a running FFmpeg session for cancellation & inspection.
class ActiveSession {
  final String taskId;
  final FFmpegSession session;
  final Stream<EncodeProgress> progress;
  final Future<void> completion;
  ActiveSession({
    required this.taskId,
    required this.session,
    required this.progress,
    required this.completion,
  });
}

/// Builds FFmpeg commands and runs sessions with progress + log streaming.
/// Never invoke FFmpeg directly from UI — go through this service.
class TranscodeService {
  TranscodeService(this._ref);
  final Ref _ref;

  ActiveSession? _active;
  final _progressController = StreamController<EncodeProgress>.broadcast();

  Stream<EncodeProgress> get progressStream => _progressController.stream;
  bool get isRunning => _active != null;

  /// Escapes file paths for safe usage inside FFmpeg filter graphs.
  /// Handles backslashes, colons, and single quotes that would break
  /// the filter syntax.
  String _escapeFilterPath(String path) {
    return path
        .replaceAll('\\', '\\\\')
        .replaceAll(':', '\\:')
        .replaceAll("'", "\\'");
  }

  /// Resolves the actual FFmpeg video encoder name based on user preference
  /// and device capability. Falls back HW → SW on mismatch.
  String _resolveVideoEncoder(TranscodePreset preset, DeviceCapability cap) {
    bool wantsHw =
        preset.encoderPref == EncoderPreference.hardware ||
        (preset.encoderPref == EncoderPreference.auto && cap.preferHardware);

    switch (preset.videoCodec) {
      case VideoCodec.h264:
        if (wantsHw && cap.supportsH264Hw) return 'h264_mediacodec';
        return 'libx264';
      case VideoCodec.hevc:
        if (wantsHw && cap.supportsHevcHw) return 'hevc_mediacodec';
        return 'libx265';
      case VideoCodec.av1:
        if (wantsHw && cap.supportsAv1Hw) return 'av1_mediacodec';
        return 'libsvtav1';
      case VideoCodec.copy:
        return 'copy';
    }
  }

  String _resolveAudioEncoder(AudioCodec codec) {
    return switch (codec) {
      AudioCodec.aac => 'aac',
      AudioCodec.opus => 'libopus',
      AudioCodec.mp3 => 'libmp3lame',
      AudioCodec.ac3 => 'ac3',
      AudioCodec.copy => 'copy',
    };
  }

  /// Builds the FFmpeg argument list for a single encode pass.
  ///
  /// Key design decisions:
  /// - Subtitle burn-in filter is placed **before** scale/fps so subtitles
  ///   render at the original video resolution, then scale resizes everything
  ///   together. Placing subtitles after scale would render them at the
  ///   scaled resolution, causing incorrect positioning/sizing.
  /// - The `si` parameter receives the **relative** subtitle stream index
  ///   (0-based among subtitle streams), not the absolute stream index.
  ///   FFmpeg's `av_find_best_stream` counts only streams of the requested
  ///   type when `wanted_stream_nb >= 0`.
  List<String> _buildArgs({
    required EncodeTask task,
    required TranscodePreset preset,
    required DeviceCapability cap,
    required String passLogPrefix,
    required bool isPassOne,
  }) {
    final args = <String>[];

    // Trimming: Seek before input for performance, but requires re-encoding
    if (preset.startTime != null && preset.startTime!.isNotEmpty) {
      args.addAll(['-ss', preset.startTime!]);
    }

    args.addAll(['-y', '-i', task.sourcePath]);

    if (preset.endTime != null && preset.endTime!.isNotEmpty) {
      args.addAll(['-to', preset.endTime!]);
    }

    // --- Filter chain ---
    // Order matters: subtitles → scale → fps → custom
    final filters = <String>[];

    // Burn-in subtitles FIRST so they render at original resolution.
    // `si` is the 0-based relative index among subtitle streams.
    if (preset.burnSubtitleIndex != null && preset.burnSubtitleIndex! >= 0) {
      final escapedPath = _escapeFilterPath(task.sourcePath);
      filters.add("subtitles='$escapedPath':si=${preset.burnSubtitleIndex}");
    }

    if (preset.resolution != null) {
      final w = preset.resolution!.split('x').first;
      filters.add('scale=$w:-2');
    }
    if (preset.framerate != null) {
      filters.add('fps=${preset.framerate}');
    }
    if (preset.filterChain != null && preset.filterChain!.isNotEmpty) {
      filters.add(preset.filterChain!);
    }
    if (filters.isNotEmpty) {
      args.addAll(['-vf', filters.join(',')]);
    }

    final vEnc = _resolveVideoEncoder(preset, cap);
    args.addAll(['-c:v', vEnc]);

    final isHw = vEnc.endsWith('_mediacodec');
    if (vEnc != 'copy') {
      if (isHw) {
        final bitrate =
            preset.videoBitrate ??
            _crfToBitrate(preset.crf, task.totalDurationSeconds) ??
            4000000;
        args.addAll(['-b:v', '${bitrate ~/ 1000}k']);
      } else if (preset.crf != null) {
        args.addAll(['-crf', '${preset.crf}']);
        if (preset.videoCodec == VideoCodec.h264) {
          args.addAll(['-preset', 'fast']);
        }
      } else if (preset.videoBitrate != null) {
        args.addAll(['-b:v', '${preset.videoBitrate! ~/ 1000}k']);
      }
    }

    if (preset.twoPass && vEnc != 'copy' && !isHw) {
      args.addAll([
        '-pass',
        isPassOne ? '1' : '2',
        '-passlogfile',
        passLogPrefix,
      ]);
      if (isPassOne) {
        args.addAll(['-an', '-f', preset.fileExtension, '/dev/null']);
      }
    }

    if (!isPassOne) {
      if (preset.removeAudio) {
        args.addAll(['-an']);
      } else {
        args.addAll([
          '-c:a',
          _resolveAudioEncoder(preset.audioCodec),
          '-b:a',
          '${preset.audioBitrate}k',
        ]);
      }
      if (preset.faststart && preset.container == ContainerFormat.mp4) {
        args.addAll(['-movflags', '+faststart']);
      }
      args.add(task.outputPath);
    }

    return args;
  }

  /// Rough CRF → target bitrate (bps) for HW fallback. Approximation only.
  int? _crfToBitrate(int? crf, double durationSeconds) {
    if (crf == null) return null;
    final base = 8000000;
    final factor = (1 - (crf - 18) * 0.12).clamp(0.15, 1.5);
    return (base * factor).toInt();
  }

  /// Starts an encode. Returns the active session handle for cancellation.
  ///
  /// Throws [StateError] if another encode is already running.
  /// The returned session's [ActiveSession.completion] clears the internal
  /// `_active` reference when it resolves (success or failure), so the
  /// caller never needs to manually reset state.
  Future<ActiveSession> start({
    required EncodeTask task,
    required TranscodePreset preset,
    required DeviceCapability capability,
  }) async {
    if (_active != null) {
      throw StateError('An encode is already running');
    }

    final log = _ref.read(loggerProvider);
    final probe = _ref.read(mediaProbeServiceProvider);

    double totalSeconds = task.totalDurationSeconds;
    if (totalSeconds <= 0) {
      try {
        final info = await probe.probe(task.sourcePath);
        totalSeconds = info.duration?.inSeconds.toDouble() ?? 0;
      } catch (e) {
        log.w('Could not probe duration; progress percent will be 0', error: e);
      }
    }

    final tempDir = await PathHelpers.ensureCacheDir('passes');
    final passLogPrefix = p.join(tempDir.path, task.id);

    /// Runs a single FFmpeg pass and returns the session + completion future.
    Future<(FFmpegSession, Future<void>)> runPass(bool isPassOne) async {
      final args = _buildArgs(
        task: task,
        preset: preset,
        cap: capability,
        passLogPrefix: passLogPrefix,
        isPassOne: isPassOne,
      );
      log.i('FFmpeg args: ${args.join(' ')}');

      final completer = Completer<void>();
      final session = await FFmpegKit.executeWithArgumentsAsync(
        args,
        (session) async {
          final rc = await session.getReturnCode();
          if (ReturnCode.isSuccess(rc)) {
            completer.complete();
          } else if (ReturnCode.isCancel(rc)) {
            completer.completeError(EncodeCancelledException());
          } else {
            completer.completeError(
              TranscodeFailedException(
                rc?.getValue() ?? -1,
                log: 'See logs screen for FFmpeg output.',
              ),
            );
          }
        },
        (line) => log.d('FFmpeg: ${line.getMessage()}'),
        (stats) {
          final pct = FormatParsers.percent(stats, totalSeconds);
          final currentSeconds = stats.getTime() / 1000.0;
          final speed = stats.getSpeed();
          final eta = FormatParsers.etaSeconds(
            currentSeconds: currentSeconds,
            totalSeconds: totalSeconds,
            speed: speed,
          );

          // Calculate bitrate manually from size (bytes) and time (ms).
          // FFmpeg's getBitrate() can be unreliable for MediaCodec.
          double bitrate = 0;
          if (stats.getTime() > 0) {
            bitrate =
                (stats.getSize().toDouble() * 8000.0) /
                stats.getTime().toDouble();
          }
          if (bitrate <= 0) {
            bitrate = stats.getBitrate().toDouble();
          }

          if (!_progressController.isClosed) {
            _progressController.add(
              EncodeProgress(
                taskId: task.id,
                percent: pct,
                fps: stats.getVideoFps().toDouble(),
                speed: speed,
                etaSeconds: eta,
                bitrateBitsPerSec: bitrate,
                frameNumber: stats.getVideoFrameNumber(),
                bytesProcessed: stats.getSize().toInt(),
              ),
            );
          }
        },
      );
      return (session, completer.future);
    }

    final (initialSession, initialCompleter) = await runPass(preset.twoPass);
    final Future<void> completion;
    if (preset.twoPass) {
      completion = () async {
        await initialCompleter;
        final (s2, c2) = await runPass(false);
        _active = ActiveSession(
          taskId: task.id,
          session: s2,
          progress: progressStream,
          completion: c2,
        );
        await c2;
      }();
    } else {
      completion = initialCompleter;
    }

    // Wrap completion so _active is always cleared when the encode finishes,
    // whether it succeeded, was cancelled, or failed. Without this, a failed
    // encode leaves _active non-null and the next start() throws StateError.
    final wrappedCompletion = () async {
      try {
        await completion;
      } finally {
        if (_active?.taskId == task.id) {
          _active = null;
        }
      }
    }();

    _active = ActiveSession(
      taskId: task.id,
      session: initialSession,
      progress: progressStream,
      completion: wrappedCompletion,
    );

    return _active!;
  }

  /// Cancels the active session. Resolves when FFmpeg has stopped.
  Future<void> cancel() async {
    final a = _active;
    _active = null;
    if (a == null) return;
    try {
      await FFmpegKit.cancel(a.session.getSessionId());
    } catch (_) {
      // Best-effort; session may already be gone
    }
  }

  /// Releases stream resources. Safe to call repeatedly.
  void dispose() {
    _progressController.close();
  }
}

final transcodeServiceProvider = Provider<TranscodeService>(
  (ref) => TranscodeService(ref),
);
