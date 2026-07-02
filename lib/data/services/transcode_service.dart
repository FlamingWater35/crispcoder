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
class TranscodeService {
  TranscodeService(this._ref);
  final Ref _ref;

  ActiveSession? _active;
  final _progressController = StreamController<EncodeProgress>.broadcast();

  Stream<EncodeProgress> get progressStream => _progressController.stream;
  bool get isRunning => _active != null;

  /// Escapes file paths for safe usage inside FFmpeg filter graphs.
  /// Colons and backslashes must be escaped to avoid parser confusion.
  String _escapeFilterPath(String path) {
    return path
        .replaceAll('\\', '\\\\')
        .replaceAll(':', '\\:')
        .replaceAll("'", "\\'");
  }

  /// Resolves the FFmpeg video encoder name based on user preference and
  /// device capability. Forces software encoding when burning subtitles
  /// because the libass `subtitles` filter is incompatible with MediaCodec's
  /// surface-based pipeline.
  String _resolveVideoEncoder(TranscodePreset preset, DeviceCapability cap) {
    bool wantsHw =
        preset.encoderPref == EncoderPreference.hardware ||
        (preset.encoderPref == EncoderPreference.auto && cap.preferHardware);

    // Subtitle burn-in uses the libass subtitles filter which requires
    // CPU-accessible frames. MediaCodec encoders operate on surfaces
    // and cannot consume filtered output, so force software here.
    if (preset.burnSubtitleIndex != null && preset.burnSubtitleIndex! >= 0) {
      wantsHw = false;
    }

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
      case VideoCodec.vp9:
        return 'libvpx-vp9';
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
      AudioCodec.flac => 'flac',
      AudioCodec.vorbis => 'libvorbis',
      AudioCodec.copy => 'copy',
    };
  }

  /// Builds the FFmpeg argument list for a single encode pass.
  /// Handles audio/subtitle extraction, video transcode with filters
  /// (subtitles, crop, scale, fps), and two-pass encoding.
  List<String> _buildArgs({
    required EncodeTask task,
    required TranscodePreset preset,
    required DeviceCapability cap,
    required String passLogPrefix,
    required bool isPassOne,
  }) {
    final args = <String>[];

    // --- Audio Extraction: no video, encode audio only ---
    if (preset.outputType == OutputType.audio) {
      if (preset.startTime != null && preset.startTime!.isNotEmpty) {
        args.addAll(['-ss', preset.startTime!]);
      }
      args.addAll(['-y', '-i', task.sourcePath]);
      if (preset.endTime != null && preset.endTime!.isNotEmpty) {
        args.addAll(['-to', preset.endTime!]);
      }
      args.addAll(['-vn', '-sn']);
      if (preset.audioCodec != AudioCodec.copy) {
        args.addAll(['-c:a', _resolveAudioEncoder(preset.audioCodec)]);
        if (preset.audioCodec != AudioCodec.flac) {
          args.addAll(['-b:a', '${preset.audioBitrate}k']);
        }
      } else {
        args.addAll(['-c:a', 'copy']);
      }
      args.add(task.outputPath);
      return args;
    }

    // --- Subtitle Extraction ---
    if (preset.outputType == OutputType.subtitle) {
      if (preset.startTime != null && preset.startTime!.isNotEmpty) {
        args.addAll(['-ss', preset.startTime!]);
      }
      args.addAll(['-y', '-i', task.sourcePath]);
      if (preset.endTime != null && preset.endTime!.isNotEmpty) {
        args.addAll(['-to', preset.endTime!]);
      }
      final subIdx = preset.burnSubtitleIndex ?? 0;
      args.addAll(['-map', '0:s:$subIdx', '-an', '-vn', '-c:s', 'srt']);
      args.add(task.outputPath);
      return args;
    }

    // --- Video Transcode ---

    bool wantsHw =
        preset.encoderPref == EncoderPreference.hardware ||
        (preset.encoderPref == EncoderPreference.auto && cap.preferHardware);

    // Force software when burning subtitles (see _resolveVideoEncoder)
    if (preset.burnSubtitleIndex != null && preset.burnSubtitleIndex! >= 0) {
      wantsHw = false;
    }

    if (wantsHw) {
      args.addAll(['-hwaccel', 'mediacodec']);
    }

    if (preset.startTime != null && preset.startTime!.isNotEmpty) {
      args.addAll(['-ss', preset.startTime!]);
    }

    args.addAll(['-y', '-i', task.sourcePath]);

    if (preset.endTime != null && preset.endTime!.isNotEmpty) {
      args.addAll(['-to', preset.endTime!]);
    }

    // --- Filter chain ---
    // Order: subtitles → crop → scale → fps → custom
    final filters = <String>[];

    // Burn-in subtitles using libass. Must come before scale so text
    // is rendered at source resolution then scaled together.
    if (preset.burnSubtitleIndex != null && preset.burnSubtitleIndex! >= 0) {
      final escaped = _escapeFilterPath(task.sourcePath);
      filters.add("subtitles='$escaped':si=${preset.burnSubtitleIndex}");
    }

    // Visual crop (fractional values from crop editor)
    if (preset.cropWidth != null &&
        preset.cropWidth! > 0 &&
        preset.cropHeight != null &&
        preset.cropHeight! > 0) {
      final w = preset.cropWidth!;
      final h = preset.cropHeight!;
      final x = preset.cropLeft ?? 0.0;
      final y = preset.cropTop ?? 0.0;
      filters.add("crop=iw*$w:ih*$h:iw*$x:ih*$y");
    } else if (preset.aspectRatio != null && preset.aspectRatio!.isNotEmpty) {
      // Aspect ratio crop: fit video into target AR by cropping edges
      final parts = preset.aspectRatio!.split(':');
      if (parts.length == 2) {
        final arW = double.tryParse(parts[0]) ?? 1;
        final arH = double.tryParse(parts[1]) ?? 1;
        if (arW > 0 && arH > 0) {
          filters.add("crop=min(iw\\,ih*$arW/$arH):min(ih\\,iw*$arH/$arW)");
        }
      }
    }

    // Resolution: fit video inside a standard 16:9 box using
    // force_original_aspect_ratio=decrease. This means a 2.39:1 video
    // set to "1080p" becomes 1920x800 (width=1920), NOT 1920x1080.
    // The conditional if(gt(iw,ih),...) swaps the box for portrait sources.
    if (preset.resolution != null && preset.resolution! > 0) {
      final res = preset.resolution!;
      const resToW = {
        2160: 3840,
        1440: 2560,
        1080: 1920,
        720: 1280,
        576: 1024,
        480: 854,
        360: 640,
        240: 426,
      };
      final boxW = resToW[res] ?? (res * 16 ~/ 9);
      final boxH = res;
      filters.add(
        'scale=if(gt(iw\\,ih)\\,$boxW\\,$boxH)'
        ':if(gt(iw\\,ih)\\,$boxH\\,$boxW)'
        ':force_original_aspect_ratio=decrease:force_divisible_by=2',
      );
    }

    // Framerate resampling via fps filter (drops/duplicates frames)
    if (preset.framerate != null) {
      filters.add('fps=${preset.framerate}');
    }
    if (preset.filterChain != null && preset.filterChain!.isNotEmpty) {
      filters.add(preset.filterChain!);
    }
    if (filters.isNotEmpty) {
      args.addAll(['-vf', filters.join(',')]);
    }

    // --- Video encoder ---
    final vEnc = _resolveVideoEncoder(preset, cap);
    args.addAll(['-c:v', vEnc]);

    final isHw = vEnc.endsWith('_mediacodec');
    if (vEnc != 'copy') {
      if (isHw) {
        // HW mediacodec requires explicit bitrate; CRF is not supported
        final bitrate =
            preset.videoBitrate ??
            _crfToBitrate(preset.crf, task.totalDurationSeconds) ??
            4000000;
        args.addAll(['-b:v', '${bitrate ~/ 1000}k']);
      } else {
        args.addAll(['-threads', '${cap.recommendedThreadCount}']);

        if (preset.crf != null) {
          args.addAll(['-crf', '${preset.crf}']);
          final swPreset = preset.videoPreset ?? 'fast';
          if (preset.videoCodec == VideoCodec.h264 ||
              preset.videoCodec == VideoCodec.hevc) {
            args.addAll(['-preset', swPreset]);
          } else if (preset.videoCodec == VideoCodec.vp9) {
            args.addAll(['-b:v', '0', '-row-mt', '1']);
          }
        } else if (preset.videoBitrate != null) {
          args.addAll(['-b:v', '${preset.videoBitrate! ~/ 1000}k']);
        }

        // Set GOP (keyframe interval) to 2x framerate for seek-friendly output.
        // This is critical for MKV containers to have proper seek indices.
        if (preset.framerate != null) {
          args.addAll(['-g', '${preset.framerate! * 2}']);
        }
      }
    }

    // Two-pass encoding (software only)
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

    // --- Pass 2 / Single pass: audio + output ---
    if (!isPassOne) {
      if (preset.removeAudio) {
        args.addAll(['-an']);
      } else {
        args.addAll(['-c:a', _resolveAudioEncoder(preset.audioCodec)]);
        if (preset.audioCodec != AudioCodec.flac &&
            preset.audioCodec != AudioCodec.copy) {
          args.addAll(['-b:a', '${preset.audioBitrate}k']);
        }
      }

      // Set output framerate metadata explicitly. The fps filter resamples
      // frames, but -r ensures the container stream metadata is correct.
      // -vsync cfr forces constant frame rate output, preventing VFR
      // issues that cause seek problems and wrong bitrate reporting.
      if (vEnc != 'copy' && preset.framerate != null) {
        args.addAll(['-r', '${preset.framerate}', '-vsync', 'cfr']);
      }

      if (preset.faststart && preset.container == ContainerFormat.mp4) {
        args.addAll(['-movflags', '+faststart']);
      }
      args.add(task.outputPath);
    }

    return args;
  }

  /// Rough CRF → target bitrate (bps) for HW fallback when CRF is set
  /// but the mediacodec encoder only supports bitrate mode.
  int? _crfToBitrate(int? crf, double durationSeconds) {
    if (crf == null) return null;
    final base = 8000000;
    final factor = (1 - (crf - 18) * 0.12).clamp(0.15, 1.5);
    return (base * factor).toInt();
  }

  /// Starts an encode session. Probes duration if missing, builds args,
  /// launches FFmpeg async with progress + log callbacks.
  /// Returns an [ActiveSession] handle for cancellation.
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

  /// Cancels the active FFmpeg session by session ID.
  Future<void> cancel() async {
    final a = _active;
    _active = null;
    if (a == null) return;
    try {
      await FFmpegKit.cancel(a.session.getSessionId());
    } catch (_) {}
  }

  void dispose() {
    _progressController.close();
  }
}

final transcodeServiceProvider = Provider<TranscodeService>(
  (ref) => TranscodeService(ref),
);
