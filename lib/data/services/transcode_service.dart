import 'dart:async';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
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

  // --- Time helpers -------------------------------------------------------

  /// Parses an `HH:MM:SS` string into a [Duration]. Returns null for empty or
  /// malformed input.
  Duration? _parseHms(String? value) {
    if (value == null || value.isEmpty) return null;
    final match = RegExp(
      r'^(\d{1,2}):([0-5]\d):([0-5]\d)$',
    ).firstMatch(value.trim());
    if (match == null) return null;
    return Duration(
      hours: int.parse(match.group(1)!),
      minutes: int.parse(match.group(2)!),
      seconds: int.parse(match.group(3)!),
    );
  }

  /// Returns the trimmed output duration in seconds when the user set both
  /// (or just an end) time. With input-side `-ss`, FFmpeg resets timestamps
  /// near zero, so `-t` (duration) is used instead of `-to` (absolute end).
  /// Returns null when no trim applies or the range is invalid.
  double? _trimDurationSeconds(String? start, String? end) {
    final endDur = _parseHms(end);
    if (endDur == null) return null;
    final base = _parseHms(start) ?? Duration.zero;
    if (endDur <= base) return null;
    return (endDur - base).inMilliseconds / 1000.0;
  }

  /// Formats a duration in seconds for FFmpeg's `-t` option.
  String _formatSeconds(double seconds) => seconds.toStringAsFixed(3);

  // --- Encoder resolution -------------------------------------------------

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

  /// Maps an audio output extension to the FFmpeg muxer that produces it.
  /// `.m4a` is written by the `ipod` muxer (the audio-only MP4 variant) —
  /// never the generic video `mp4` muxer; `.mka` by `matroska`. Opus has no
  /// standalone muxer named after the codec — it is written into an Ogg
  /// container, so `.opus` uses the `ogg` muxer. Everything else
  /// (mp3/ac3/flac/ogg) has a muxer named after the extension.
  String _resolveAudioMuxer(String extension) {
    return switch (extension) {
      'm4a' => 'ipod',
      'mka' => 'matroska',
      'opus' => 'ogg',
      _ => extension,
    };
  }

  // --- Bitrate helpers (all in kbps) --------------------------------------

  /// Rough CRF → target bitrate (kbps) used as a fallback for hardware
  /// encoders that only support bitrate mode.
  int? _crfToBitrateKbps(int? crf) {
    if (crf == null) return null;
    const base = 8000; // kbps (8 Mbps at CRF 18)
    final factor = (1 - (crf - 18) * 0.12).clamp(0.15, 1.5);
    return (base * factor).round();
  }

  /// Resolution/framerate-aware default bitrate (kbps) for hardware encoders.
  int _defaultVideoBitrateKbps(TranscodePreset preset, double? effectiveFps) {
    final fps = effectiveFps ?? preset.framerate ?? 30;
    final base = switch (preset.resolution ?? 1080) {
      2160 => 20000,
      1440 => 12000,
      1080 => 6000,
      720 => 3500,
      480 => 1800,
      360 => 1200,
      _ => 2500,
    };
    final fpsFactor = fps / 30.0;
    var result = (base * fpsFactor).round();
    if (preset.videoCodec == VideoCodec.hevc ||
        preset.videoCodec == VideoCodec.av1) {
      result = (result * 0.75).round();
    }
    return result.clamp(800, 60000);
  }

  /// Resolves the effective video bitrate in kbps. [TranscodePreset.videoBitrate]
  /// is already kbps; otherwise falls back to CRF- or resolution-based guesses.
  int _resolveVideoBitrateKbps(
    TranscodePreset preset,
    double? effectiveFps,
  ) {
    if (preset.videoBitrate != null) return preset.videoBitrate!;
    final fromCrf = _crfToBitrateKbps(preset.crf);
    if (fromCrf != null) return fromCrf;
    return _defaultVideoBitrateKbps(preset, effectiveFps);
  }

  /// Whether generic FFmpeg two-pass (`-pass 1/2`) is reliable for this
  /// preset. Only software H.264 (libx264) with an explicit bitrate target
  /// is supported — CRF is single-pass by design, and libx265/SVT-AV1/VP9
  /// need encoder-specific pass handling. Anything else is silently
  /// downgraded to single pass.
  bool _supportsTwoPass(TranscodePreset preset, DeviceCapability cap) {
    if (!preset.twoPass) return false;
    if (preset.videoCodec != VideoCodec.h264) return false;
    if (preset.crf != null) return false; // CRF is inherently single-pass
    final vEnc = _resolveVideoEncoder(preset, cap);
    return vEnc != 'copy' && !vEnc.endsWith('_mediacodec');
  }

  /// Builds the FFmpeg argument list for a single encode pass.
  ///
  /// Correctness rules enforced here:
  /// - `preset.videoBitrate` is **kbps** and passed as `${value}k` (never
  ///   divided by 1000 again).
  /// - Trimming uses input-side `-ss` plus `-t <duration>` (never `-to` after
  ///   input-side seeking, which would measure from the seek point).
  /// - A null framerate preserves the source timing; `fps=` / `-r` /
  ///   `-fps_mode cfr` are only emitted when the user explicitly set one.
  /// - Video copy never emits filters (subtitle burn-in, crop, scale, fps).
  /// - `-hwaccel mediacodec` is only enabled for pure hardware pipelines
  ///   (hardware encoder AND no filters), because filters need CPU frames.
  /// - Playback compatibility flags (`-pix_fmt yuv420p`, `-avoid_negative_ts`,
  ///   `-max_muxing_queue_size`) are added for encoded video.
  @visibleForTesting
  List<String> buildCommandArgs({
    required EncodeTask task,
    required TranscodePreset preset,
    required DeviceCapability cap,
  }) {
    return _buildArgs(
      task: task,
      preset: preset,
      cap: cap,
      passLogPrefix: 'test',
      isPassOne: false,
    );
  }

  List<String> _buildArgs({
    required EncodeTask task,
    required TranscodePreset preset,
    required DeviceCapability cap,
    required String passLogPrefix,
    required bool isPassOne,
  }) {
    final args = <String>[];

    final startTime = preset.startTime?.trim();
    final endTime = preset.endTime?.trim();
    final trimSeconds = _trimDurationSeconds(startTime, endTime);

    void addInputSeekAndTrim() {
      if (startTime != null && startTime.isNotEmpty) {
        args.addAll(['-ss', startTime]);
      }
      args.addAll(['-y', '-i', task.sourcePath]);
      if (trimSeconds != null) {
        args.addAll(['-t', _formatSeconds(trimSeconds)]);
      }
    }

    // --- Audio Extraction: no video, encode audio only ---
    if (preset.outputType == OutputType.audio) {
      addInputSeekAndTrim();
      args.addAll(['-vn', '-sn']);
      if (preset.audioCodec != AudioCodec.copy) {
        args.addAll(['-c:a', _resolveAudioEncoder(preset.audioCodec)]);
        if (preset.audioCodec != AudioCodec.flac) {
          args.addAll(['-b:a', '${preset.audioBitrate}k']);
        }
      } else {
        args.addAll(['-c:a', 'copy']);
      }
      // Force the muxer matching the output extension. Without -f, FFmpeg
      // auto-guesses a container from the output filename; `.m4a` is
      // recognized but the generic `mp4` muxer is chosen for it, and for
      // some codecs the guess can produce a video container. Forcing the
      // correct muxer guarantees the file is the audio container the
      // extension promises.
      final ext = preset.fileExtension;
      args.addAll(['-f', _resolveAudioMuxer(ext)]);
      args.add(task.outputPath);
      return args;
    }

    // --- Subtitle Extraction ---
    if (preset.outputType == OutputType.subtitle) {
      addInputSeekAndTrim();
      final subIdx = preset.burnSubtitleIndex ?? 0;
      // Codec and muxer follow the selected output format: `srt` for SRT,
      // `ass` for ASS (SSA is re-encoded to ASS via libass-compatible ass
      // encoder). Forcing the muxer guarantees the output file matches the
      // extension the preset promises.
      final subExt = preset.fileExtension;
      args.addAll([
        '-map',
        '0:s:$subIdx',
        '-an',
        '-vn',
        '-c:s',
        subExt,
        '-f',
        subExt,
      ]);
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

    final vEnc = _resolveVideoEncoder(preset, cap);
    final isHw = vEnc.endsWith('_mediacodec');

    // Effective output framerate: explicit preset wins; otherwise fall back
    // to the probed source rate so hardware encoders and the GOP interval
    // don't assume a wrong 30 fps on 23.976/29.97/VFR sources.
    final double? effectiveFps =
        preset.framerate?.toDouble() ?? task.sourceFrameRate;

    // --- Filter chain (never for video copy / passthrough) ---
    // Order: subtitles → crop → scale → fps → custom
    final filters = <String>[];
    if (vEnc != 'copy') {
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

      // Framerate resampling. Only when explicitly requested: a null
      // framerate means "preserve source timing" (important for 23.976/29.97
      // and VFR sources — rounding and forcing CFR would corrupt them).
      if (preset.framerate != null) {
        filters.add('fps=${preset.framerate}');
      }
      if (preset.filterChain != null && preset.filterChain!.isNotEmpty) {
        filters.add(preset.filterChain!);
      }
    }

    // Hardware decode requires a pure hardware pipeline: hardware encoder,
    // no filters, no subtitle burn-in. Filters need CPU-accessible frames,
    // so mixing `-hwaccel mediacodec` with `-vf` is unreliable.
    final useHardwareDecode = wantsHw && isHw && filters.isEmpty;
    if (useHardwareDecode) {
      args.addAll(['-hwaccel', 'mediacodec']);
    }

    addInputSeekAndTrim();

    // Playback compatibility for video outputs.
    args.addAll([
      '-avoid_negative_ts', 'make_zero',
      '-max_muxing_queue_size', '1024',
    ]);

    if (filters.isNotEmpty) {
      args.addAll(['-vf', filters.join(',')]);
    }

    // --- Video encoder ---
    args.addAll(['-c:v', vEnc]);

    if (vEnc != 'copy') {
      if (isHw) {
        // HW mediacodec requires explicit bitrate; CRF is not supported
        final bitrateKbps = _resolveVideoBitrateKbps(preset, effectiveFps);
        args.addAll(['-b:v', '${bitrateKbps}k']);
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
          // kbps value passed straight through; no unit conversion.
          args.addAll(['-b:v', '${preset.videoBitrate}k']);
        }

        // Broad compatibility: force 4:2:0 8-bit so players without
        // 10-bit decode support can play the output. Skipped for MediaCodec
        // encoders which manage their own surface format.
        args.addAll(['-pix_fmt', 'yuv420p']);
      }

      // Set GOP (keyframe interval) to 2x framerate for seek-friendly
      // output. Critical for MKV containers to have proper seek indices.
      // Uses the effective (explicit or source) framerate, never a blind
      // 30 fps assumption. -g is an integer codec option, so round.
      final fps = effectiveFps ?? 30;
      args.addAll(['-g', '${(fps * 2).round()}']);

      // Two-pass encoding (software H.264/HEVC only)
      if (_supportsTwoPass(preset, cap)) {
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

      // Subtitles are burned into the video frames, so don't also mux the
      // original subtitle stream — default stream selection would duplicate
      // it into mkv/mp4 outputs.
      if (preset.burnSubtitleIndex != null && preset.burnSubtitleIndex! >= 0) {
        args.addAll(['-sn']);
      }

      // Only force constant frame rate when the user explicitly chose one.
      // `-fps_mode cfr` (modern alias of `-vsync cfr`) sets container
      // metadata; the fps filter already resampled the frames.
      if (vEnc != 'copy' && preset.framerate != null) {
        args.addAll(['-r', '${preset.framerate}', '-fps_mode', 'cfr']);
      } else if (isHw && effectiveFps != null) {
        // MediaCodec surface pipelines need an explicit CFR target even when
        // preserving the source rate — without -r, a VFR/23.976 source can
        // produce wrong-rate output. Derive it from the probed source fps.
        args.addAll(['-r', '$effectiveFps', '-fps_mode', 'cfr']);
      }

      if (preset.faststart && preset.container == ContainerFormat.mp4) {
        args.addAll(['-movflags', '+faststart']);
      }
      args.add(task.outputPath);
    }

    return args;
  }

  /// Total media seconds the encoder will process — used for progress
  /// percentages. When trimming, this is the trimmed duration, not the full
  /// source duration.
  double _progressTotalSeconds(EncodeTask task, TranscodePreset preset) {
    final trim = _trimDurationSeconds(
      preset.startTime?.trim(),
      preset.endTime?.trim(),
    );
    if (trim != null) return trim;
    return task.totalDurationSeconds;
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
    _cancelRequested = false;

    final log = _ref.read(loggerProvider);
    final probe = _ref.read(mediaProbeServiceProvider);

    double totalSeconds = _progressTotalSeconds(task, preset);
    if (totalSeconds <= 0) {
      try {
        final info = await probe.probe(task.sourcePath);
        totalSeconds =
            (info.duration?.inMilliseconds ?? 0) / 1000.0;
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

    final usesTwoPass = _supportsTwoPass(preset, capability);
    final (initialSession, initialCompleter) = await runPass(usesTwoPass);
    final Future<void> completion;
    if (usesTwoPass) {
      completion = () async {
        await initialCompleter;
        // cancel() is a no-op for a completed session, so without this gate
        // pass 2 would run to completion even though the user cancelled.
        if (_cancelRequested) {
          throw EncodeCancelledException();
        }
        final (s2, c2) = await runPass(false);
        // Re-check after launch: cancel() may have run while pass 2 was
        // starting (the gate above and the _active reassignment are not
        // atomic). In that case abort the just-started pass 2 instead of
        // resurrecting _active and letting it run to completion.
        if (_cancelRequested) {
          await FFmpegKit.cancel(s2.getSessionId());
          throw EncodeCancelledException();
        }
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

  /// Cancels the active FFmpeg session by session ID. Also sets the
  /// two-pass boundary flag so a cancel during the pass1→pass2 gap prevents
  /// pass 2 from starting.
  Future<void> cancel() async {
    _cancelRequested = true;
    final a = _active;
    _active = null;
    if (a == null) return;
    try {
      await FFmpegKit.cancel(a.session.getSessionId());
    } catch (_) {}
  }

  /// Set when the user cancels; reset at the start of each session. Used to
  /// abort a two-pass encode between passes, where the completed pass-1
  /// session is no longer cancellable.
  bool _cancelRequested = false;

  void dispose() {
    _progressController.close();
  }
}

final transcodeServiceProvider = Provider<TranscodeService>(
  (ref) => TranscodeService(ref),
);
