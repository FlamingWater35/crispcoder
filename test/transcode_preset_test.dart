import 'package:crispcoder/data/models/transcode_preset.dart';
import 'package:flutter_test/flutter_test.dart';

TranscodePreset _base({
  VideoCodec videoCodec = VideoCodec.h264,
  AudioCodec audioCodec = AudioCodec.aac,
  ContainerFormat container = ContainerFormat.mp4,
  String? sourceAudioCodec,
  String? sourceVideoCodec,
  int? resolution,
  int? framerate,
  int? burnSubtitleIndex,
  double? cropWidth,
  double? cropHeight,
}) {
  return TranscodePreset(
    id: 'p',
    name: 'P',
    category: 'Test',
    videoCodec: videoCodec,
    crf: 23,
    audioCodec: audioCodec,
    audioBitrate: 160,
    container: container,
    sourceAudioCodec: sourceAudioCodec,
    sourceVideoCodec: sourceVideoCodec,
    resolution: resolution,
    framerate: framerate,
    burnSubtitleIndex: burnSubtitleIndex,
    cropWidth: cropWidth,
    cropHeight: cropHeight,
  );
}

void main() {
  group('audio copy file extension', () {
    test('m4a when source audio is aac', () {
      final p = _base(
        audioCodec: AudioCodec.copy,
        sourceAudioCodec: 'aac',
        container: ContainerFormat.mkv,
      ).copyWith(outputType: OutputType.audio);
      expect(p.fileExtension, 'm4a');
    });

    test('mp3/opus/flac/ac3/ogg follow the source codec', () {
      expect(
        _base(audioCodec: AudioCodec.copy, sourceAudioCodec: 'mp3')
            .copyWith(outputType: OutputType.audio)
            .fileExtension,
        'mp3',
      );
      expect(
        _base(audioCodec: AudioCodec.copy, sourceAudioCodec: 'opus')
            .copyWith(outputType: OutputType.audio)
            .fileExtension,
        'opus',
      );
      expect(
        _base(audioCodec: AudioCodec.copy, sourceAudioCodec: 'flac')
            .copyWith(outputType: OutputType.audio)
            .fileExtension,
        'flac',
      );
      expect(
        _base(audioCodec: AudioCodec.copy, sourceAudioCodec: 'ac3')
            .copyWith(outputType: OutputType.audio)
            .fileExtension,
        'ac3',
      );
      expect(
        _base(audioCodec: AudioCodec.copy, sourceAudioCodec: 'vorbis')
            .copyWith(outputType: OutputType.audio)
            .fileExtension,
        'ogg',
      );
    });

    test('falls back to mka for unknown/dts source audio', () {
      expect(
        _base(audioCodec: AudioCodec.copy, sourceAudioCodec: 'dts')
            .copyWith(outputType: OutputType.audio)
            .fileExtension,
        'mka',
      );
      expect(
        _base(audioCodec: AudioCodec.copy, sourceAudioCodec: null)
            .copyWith(outputType: OutputType.audio)
            .fileExtension,
        'mka',
      );
    });
  });

  group('subtitle file extension', () {
    test('srt by default and when srt format selected', () {
      expect(
        _base().copyWith(outputType: OutputType.subtitle).fileExtension,
        'srt',
      );
      expect(
        _base()
            .copyWith(
              outputType: OutputType.subtitle,
              subtitleFormat: SubtitleFormat.srt,
            )
            .fileExtension,
        'srt',
      );
    });

    test('ass when ass format selected', () {
      expect(
        _base()
            .copyWith(
              outputType: OutputType.subtitle,
              subtitleFormat: SubtitleFormat.ass,
            )
            .fileExtension,
        'ass',
      );
    });
  });

  group('compatibilityIssues', () {
    test('valid mp4 h264+aac has no issues', () {
      expect(_base().compatibilityIssues(), isEmpty);
    });

    test('webm + h264 video is rejected', () {
      final issues = _base(
        container: ContainerFormat.webm,
        videoCodec: VideoCodec.h264,
        audioCodec: AudioCodec.opus,
      ).compatibilityIssues();
      expect(issues, contains(CompatibilityIssue.webmVideoUnsupported));
      expect(issues, isNot(contains(CompatibilityIssue.webmAudioUnsupported)));
    });

    test('webm + aac audio is rejected', () {
      final issues = _base(
        container: ContainerFormat.webm,
        videoCodec: VideoCodec.vp9,
        audioCodec: AudioCodec.aac,
      ).compatibilityIssues();
      expect(issues, contains(CompatibilityIssue.webmAudioUnsupported));
    });

    test('webm + vp9 + opus is valid', () {
      expect(
        _base(
          container: ContainerFormat.webm,
          videoCodec: VideoCodec.vp9,
          audioCodec: AudioCodec.opus,
        ).compatibilityIssues(),
        isEmpty,
      );
    });

    test('webm copy needs vp8/vp9/av1 source video', () {
      final ok = _base(
        container: ContainerFormat.webm,
        videoCodec: VideoCodec.copy,
        audioCodec: AudioCodec.copy,
        sourceVideoCodec: 'vp9',
        sourceAudioCodec: 'opus',
      ).compatibilityIssues();
      expect(ok, isEmpty);

      final bad = _base(
        container: ContainerFormat.webm,
        videoCodec: VideoCodec.copy,
        audioCodec: AudioCodec.copy,
        sourceVideoCodec: 'h264',
        sourceAudioCodec: 'opus',
      ).compatibilityIssues();
      expect(bad, contains(CompatibilityIssue.webmVideoUnsupported));
    });

    test('mp4 rejects opus/vorbis audio', () {
      final issues = _base(
        container: ContainerFormat.mp4,
        audioCodec: AudioCodec.opus,
      ).compatibilityIssues();
      expect(issues, contains(CompatibilityIssue.mp4AudioUnsupported));

      final copyIssues = _base(
        container: ContainerFormat.mp4,
        audioCodec: AudioCodec.copy,
        sourceAudioCodec: 'opus',
      ).compatibilityIssues();
      expect(copyIssues, contains(CompatibilityIssue.mp4AudioUnsupported));
    });

    test('video copy with filters is rejected', () {
      final issues = _base(
        videoCodec: VideoCodec.copy,
        resolution: 720,
      ).compatibilityIssues();
      expect(issues, contains(CompatibilityIssue.videoCopyWithFilters));

      final burnIssues = _base(
        videoCodec: VideoCodec.copy,
        burnSubtitleIndex: 0,
      ).compatibilityIssues();
      expect(burnIssues, contains(CompatibilityIssue.videoCopyWithFilters));

      final cropIssues = _base(
        videoCodec: VideoCodec.copy,
        cropWidth: 0.8,
        cropHeight: 0.8,
      ).compatibilityIssues();
      expect(cropIssues, contains(CompatibilityIssue.videoCopyWithFilters));
    });

    test('video copy without filters is valid', () {
      expect(
        _base(
          videoCodec: VideoCodec.copy,
          sourceVideoCodec: 'h264',
          sourceAudioCodec: 'aac',
        ).compatibilityIssues(),
        isEmpty,
      );
    });

    test('container rules are skipped for audio/subtitle extraction', () {
      // An invalid video combo (webm+h264) is fine for audio extraction,
      // where the container is ignored (extension-only output).
      expect(
        _base(
          container: ContainerFormat.webm,
          videoCodec: VideoCodec.h264,
          audioCodec: AudioCodec.aac,
        ).copyWith(outputType: OutputType.audio).compatibilityIssues(),
        isEmpty,
      );
      expect(
        _base(
          container: ContainerFormat.webm,
          videoCodec: VideoCodec.h264,
          audioCodec: AudioCodec.aac,
        ).copyWith(outputType: OutputType.subtitle).compatibilityIssues(),
        isEmpty,
      );
    });
  });
}
