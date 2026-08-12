import 'package:crispcoder/data/models/device_capability.dart';
import 'package:crispcoder/data/models/encode_task.dart';
import 'package:crispcoder/data/models/transcode_preset.dart';
import 'package:crispcoder/data/services/transcode_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
TranscodePreset _preset({
  VideoCodec videoCodec = VideoCodec.h264,
  int? crf = 23,
  int? videoBitrate,
  int? resolution,
  int? framerate,
  String? startTime,
  String? endTime,
  AudioCodec audioCodec = AudioCodec.aac,
  ContainerFormat container = ContainerFormat.mp4,
  EncoderPreference encoderPref = EncoderPreference.software,
  int? burnSubtitleIndex,
  bool removeAudio = false,
}) {
  return TranscodePreset(
    id: 't1',
    name: 'Test',
    category: 'Test',
    videoCodec: videoCodec,
    crf: crf,
    videoBitrate: videoBitrate,
    resolution: resolution,
    framerate: framerate,
    audioCodec: audioCodec,
    audioBitrate: 160,
    container: container,
    encoderPref: encoderPref,
    startTime: startTime,
    endTime: endTime,
    burnSubtitleIndex: burnSubtitleIndex,
    removeAudio: removeAudio,
  );
}

EncodeTask _task({
  TranscodePreset? preset,
  double duration = 100,
  double? sourceFrameRate,
}) {
  return EncodeTask(
    id: 'task1',
    sourcePath: '/tmp/input.mp4',
    sourceName: 'input.mp4',
    outputPath: '/tmp/output.mp4',
    preset: preset ?? _preset(),
    createdAt: DateTime(2024, 1, 1),
    totalDurationSeconds: duration,
    sourceFrameRate: sourceFrameRate,
  );
}

const _cap = DeviceCapability(
  manufacturer: 'test',
  model: 'test',
  sdkInt: 33,
  abis: ['arm64-v8a'],
  supportsH264Hw: true,
  supportsHevcHw: true,
  supportsAv1Hw: false,
  recommendedThreadCount: 8,
);

void main() {
  final service = ProviderContainer().read(transcodeServiceProvider);

  group('bitrate unit handling (kbps)', () {
    test('explicit videoBitrate is passed as kbps, not divided by 1000', () {
      final args = service.buildCommandArgs(
        task: _task(preset: _preset(crf: null, videoBitrate: 4000)),
        preset: _preset(crf: null, videoBitrate: 4000),
        cap: _cap,
      );

      final bvIndex = args.indexOf('-b:v');
      expect(bvIndex, greaterThanOrEqualTo(0));
      expect(args[bvIndex + 1], '4000k');
      // Regression guard: the old bug produced `4k`.
      expect(args, isNot(contains('4k')));
    });

    test('CRF-based bitrate fallback for hardware uses kbps unit', () {
      final args = service.buildCommandArgs(
        task: _task(),
        preset: _preset(crf: 18, encoderPref: EncoderPreference.hardware),
        cap: _cap,
      );

      final bvIndex = args.indexOf('-b:v');
      expect(bvIndex, greaterThanOrEqualTo(0));
      // CRF 18 → base 8000 kbps.
      expect(args[bvIndex + 1], '8000k');
    });

    test('software bitrate mode passes kbps through unchanged', () {
      final args = service.buildCommandArgs(
        task: _task(),
        preset: _preset(crf: null, videoBitrate: 2500),
        cap: _cap,
      );

      final bvIndex = args.indexOf('-b:v');
      expect(args[bvIndex + 1], '2500k');
      expect(args, isNot(contains('2k')));
    });
  });

  group('trimming', () {
    test('uses -t duration after input-side -ss instead of -to', () {
      final args = service.buildCommandArgs(
        task: _task(),
        preset: _preset(startTime: '00:00:10', endTime: '00:00:20'),
        cap: _cap,
      );

      expect(args, contains('-ss'));
      expect(args[args.indexOf('-ss') + 1], '00:00:10');
      expect(args, contains('-t'));
      expect(args[args.indexOf('-t') + 1], '10.000');
      // The buggy `-to` must never be emitted after an input-side seek.
      expect(args, isNot(contains('-to')));
    });

    test('start-only trim keeps the full clip from the start point', () {
      final args = service.buildCommandArgs(
        task: _task(),
        preset: _preset(startTime: '00:00:05'),
        cap: _cap,
      );

      expect(args, contains('-ss'));
      expect(args, isNot(contains('-to')));
      expect(args, isNot(contains('-t')));
    });

    test('no trim when no times set', () {
      final args = service.buildCommandArgs(
        task: _task(),
        preset: _preset(),
        cap: _cap,
      );

      expect(args, isNot(contains('-ss')));
      expect(args, isNot(contains('-to')));
      expect(args, isNot(contains('-t')));
    });
  });

  group('framerate passthrough', () {
    test('null framerate preserves source timing (no fps/-r/-fps_mode)', () {
      final args = service.buildCommandArgs(
        task: _task(),
        preset: _preset(framerate: null, resolution: 1080),
        cap: _cap,
      );

      expect(args, isNot(contains('fps=')));
      expect(args, isNot(contains('-r')));
      expect(args, isNot(contains('-fps_mode')));
      expect(args, isNot(contains('-vsync')));
    });

    test('explicit framerate adds fps filter and cfr metadata', () {
      final args = service.buildCommandArgs(
        task: _task(),
        preset: _preset(framerate: 30),
        cap: _cap,
      );

      expect(args, contains('-vf'));
      expect(args[args.indexOf('-vf') + 1], contains('fps=30'));
      expect(args, contains('-r'));
      expect(args, contains('-fps_mode'));
      expect(args[args.indexOf('-fps_mode') + 1], 'cfr');
    });
  });

  group('subtitle burn-in', () {
    test('burn-in adds -sn so the original subtitle stream is not duplicated', () {
      final preset = _preset(
        burnSubtitleIndex: 0,
        framerate: null,
        resolution: null,
      );
      final args = service.buildCommandArgs(
        task: _task(preset: preset),
        preset: preset,
        cap: _cap,
      );

      expect(args, contains('-vf'));
      expect(args[args.indexOf('-vf') + 1], contains('subtitles='));
      expect(args, contains('-sn'));
    });

    test('no -sn when subtitles are not burned', () {
      final args = service.buildCommandArgs(
        task: _task(),
        preset: _preset(),
        cap: _cap,
      );
      expect(args, isNot(contains('-sn')));
    });
  });

  group('video copy (passthrough)', () {
    test('copy emits no video filters even when crop/fps/burn configured', () {
      final preset = TranscodePreset(
        id: 'copy',
        name: 'Copy',
        category: 'Test',
        videoCodec: VideoCodec.copy,
        crf: null,
        resolution: 720,
        framerate: 30,
        cropLeft: 0.1,
        cropTop: 0.1,
        cropWidth: 0.8,
        cropHeight: 0.8,
        burnSubtitleIndex: 0,
        audioCodec: AudioCodec.aac,
        audioBitrate: 160,
        container: ContainerFormat.mkv,
      );

      final args = service.buildCommandArgs(
        task: _task(preset: preset),
        preset: preset,
        cap: _cap,
      );

      expect(args, contains('-c:v'));
      expect(args[args.indexOf('-c:v') + 1], 'copy');
      expect(args, isNot(contains('-vf')));
      expect(args, isNot(contains('subtitles=')));
      // Encoder options must be skipped for copy.
      expect(args, isNot(contains('-crf')));
      expect(args, isNot(contains('-b:v')));
      expect(args, isNot(contains('-pix_fmt')));
    });
  });

  group('hardware acceleration', () {
    test('-hwaccel mediacodec only with hw encoder and no filters', () {
      final args = service.buildCommandArgs(
        task: _task(),
        preset: _preset(
          crf: null,
          videoBitrate: 4000,
          resolution: null,
          framerate: null,
          encoderPref: EncoderPreference.hardware,
        ),
        cap: _cap,
      );

      expect(args, contains('-hwaccel'));
      expect(args[args.indexOf('-hwaccel') + 1], 'mediacodec');
      expect(args[args.indexOf('-c:v') + 1], 'h264_mediacodec');
      expect(args, isNot(contains('-vf')));
    });

    test('hw decode disabled when filters are present', () {
      final args = service.buildCommandArgs(
        task: _task(),
        preset: _preset(
          crf: null,
          videoBitrate: 4000,
          resolution: 1080,
          framerate: 30,
          encoderPref: EncoderPreference.hardware,
        ),
        cap: _cap,
      );

      // Encoder is still hardware, but decode must fall back to software
      // because scale/fps filters need CPU frames.
      expect(args[args.indexOf('-c:v') + 1], 'h264_mediacodec');
      expect(args, isNot(contains('-hwaccel')));
      expect(args, contains('-vf'));
    });

    test('unsupported hw codec falls back to software and no hwaccel', () {
      final args = service.buildCommandArgs(
        task: _task(),
        preset: _preset(
          videoCodec: VideoCodec.av1,
          crf: null,
          videoBitrate: 4000,
          encoderPref: EncoderPreference.hardware,
        ),
        cap: _cap,
      );

      expect(args[args.indexOf('-c:v') + 1], 'libsvtav1');
      expect(args, isNot(contains('-hwaccel')));
    });

    test('hw encoder with null framerate derives -r from source fps', () {
      final preset = _preset(
        crf: null,
        videoBitrate: 4000,
        framerate: null,
        encoderPref: EncoderPreference.hardware,
      );
      final args = service.buildCommandArgs(
        task: _task(preset: preset, sourceFrameRate: 23.976),
        preset: preset,
        cap: _cap,
      );

      expect(args[args.indexOf('-c:v') + 1], 'h264_mediacodec');
      expect(args, contains('-r'));
      expect(args[args.indexOf('-r') + 1], '23.976');
      expect(args, contains('-fps_mode'));
      // GOP falls back to the source rate (rounded to an integer), not a
      // blind 30 fps.
      expect(args, contains('-g'));
      expect(args[args.indexOf('-g') + 1], '48');
    });
  });

  group('audio/subtitle extraction muxer', () {
    test('audio extraction forces a muxer matching the extension', () {
      final args = service.buildCommandArgs(
        task: _task(),
        preset: _preset().copyWith(outputType: OutputType.audio),
        cap: _cap,
      );

      expect(args.last, '/tmp/output.mp4');
      expect(args[args.length - 2], 'ipod');
      expect(args[args.length - 3], '-f');
      expect(args, contains('-vn'));
      expect(args, contains('-sn'));
      expect(args, isNot(contains('-c:v')));
    });

    test('audio aac uses the ipod (m4a) muxer, not the video mp4 muxer', () {
      final preset = _preset().copyWith(outputType: OutputType.audio);
      final args = service.buildCommandArgs(
        task: _task(preset: preset),
        preset: preset,
        cap: _cap,
      );

      expect(args, contains('-f'));
      expect(args[args.indexOf('-f') + 1], 'ipod');
      // Regression guard: generic video mp4 muxer must not be chosen.
      expect(args, isNot(contains('mp4')));
    });

    test('audio mp3 forces the mp3 muxer', () {
      final preset = _preset(
        audioCodec: AudioCodec.mp3,
      ).copyWith(outputType: OutputType.audio);
      final args = service.buildCommandArgs(
        task: _task(preset: preset),
        preset: preset,
        cap: _cap,
      );

      expect(args, contains('-f'));
      expect(args[args.indexOf('-f') + 1], 'mp3');
      expect(args[args.indexOf('-c:a') + 1], 'libmp3lame');
    });

    test('subtitle extraction forces the srt muxer', () {
      final preset = _preset(
        burnSubtitleIndex: 1,
      ).copyWith(outputType: OutputType.subtitle);
      final args = service.buildCommandArgs(
        task: _task(preset: preset),
        preset: preset,
        cap: _cap,
      );

      expect(args, contains('-f'));
      expect(args[args.indexOf('-f') + 1], 'srt');
      expect(args, contains('-map'));
      expect(args[args.indexOf('-map') + 1], '0:s:1');
      expect(args, contains('-c:s'));
      expect(args[args.indexOf('-c:s') + 1], 'srt');
      expect(args.last, '/tmp/output.mp4');
    });

    test('subtitle ass format uses the ass codec and muxer', () {
      final preset = _preset(
        burnSubtitleIndex: 1,
      ).copyWith(
        outputType: OutputType.subtitle,
        subtitleFormat: SubtitleFormat.ass,
      );
      final args = service.buildCommandArgs(
        task: _task(preset: preset),
        preset: preset,
        cap: _cap,
      );

      expect(args, contains('-f'));
      expect(args[args.indexOf('-f') + 1], 'ass');
      expect(args[args.indexOf('-c:s') + 1], 'ass');
      expect(args[args.indexOf('-map') + 1], '0:s:1');
      expect(args, contains('-an'));
      expect(args, contains('-vn'));
    });
  });

  group('compatibility flags', () {
    test('encoded video gets pix_fmt yuv420p + negative ts + mux queue', () {
      final args = service.buildCommandArgs(
        task: _task(),
        preset: _preset(),
        cap: _cap,
      );

      expect(args, contains('-pix_fmt'));
      expect(args[args.indexOf('-pix_fmt') + 1], 'yuv420p');
      expect(args, contains('-avoid_negative_ts'));
      expect(args, contains('-max_muxing_queue_size'));
    });

    test('mp4 + faststart adds movflags', () {
      final args = service.buildCommandArgs(
        task: _task(),
        preset: _preset(),
        cap: _cap,
      );

      expect(args, contains('-movflags'));
      expect(args[args.indexOf('-movflags') + 1], '+faststart');
    });
  });

  group('two-pass', () {
    test('software h264 two-pass requires bitrate mode (crf must be null)', () {
      // CRF mode: two-pass is invalid for x264, so -pass must NOT appear.
      final crfPreset = _preset().copyWith(twoPass: true);
      final crfArgs = service.buildCommandArgs(
        task: _task(preset: crfPreset),
        preset: crfPreset,
        cap: _cap,
      );
      expect(crfArgs, isNot(contains('-pass')));

      // Bitrate mode: two-pass is valid.
      final bitratePreset = _preset(
        crf: null,
        videoBitrate: 4000,
      ).copyWith(twoPass: true);
      final args = service.buildCommandArgs(
        task: _task(preset: bitratePreset),
        preset: bitratePreset,
        cap: _cap,
      );
      expect(args, contains('-pass'));
      expect(args[args.indexOf('-pass') + 1], '2');
    });

    test('hevc + opus (Max Compression preset) two-pass is downgraded', () {
      final preset = _preset(
        videoCodec: VideoCodec.hevc,
        audioCodec: AudioCodec.opus,
        container: ContainerFormat.mkv,
        resolution: null,
      ).copyWith(twoPass: true);

      final args = service.buildCommandArgs(
        task: _task(preset: preset),
        preset: preset,
        cap: _cap,
      );

      // libx265 generic -pass is not reliable; expect single pass.
      expect(args, isNot(contains('-pass')));
      expect(args, contains('-c:a'));
      expect(args[args.indexOf('-c:a') + 1], 'libopus');
    });
  });
}
