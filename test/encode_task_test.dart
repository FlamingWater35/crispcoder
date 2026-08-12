import 'package:crispcoder/data/models/encode_task.dart';
import 'package:crispcoder/data/models/transcode_preset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  EncodeTask task({
    String? sourceName,
    String outputPath = '/out/out.mp4',
    OutputType outputType = OutputType.video,
  }) {
    return EncodeTask(
      id: 't',
      sourcePath: '/in/in.mp4',
      sourceName: sourceName,
      outputPath: outputPath,
      preset: TranscodePreset(
        id: 'p',
        name: 'P',
        category: 'Test',
        outputType: outputType,
        videoCodec: VideoCodec.h264,
        crf: 23,
        audioCodec: AudioCodec.aac,
        audioBitrate: 160,
        container: ContainerFormat.mp4,
      ),
      createdAt: DateTime(2024, 1, 1),
    );
  }

  group('displayTitle', () {
    test('video tasks are titled by the source name', () {
      expect(
        task(sourceName: 'Perfect_World.mp4').displayTitle,
        'Perfect_World.mp4',
      );
    });

    test('video tasks fall back to the output basename without a source name',
        () {
      expect(
        task(sourceName: null, outputPath: '/out/clip.mp4').displayTitle,
        'clip.mp4',
      );
    });

    test('audio tasks are titled by the output artifact, not the source', () {
      expect(
        task(
          sourceName: 'Perfect_World.mp4',
          outputPath: '/docs/CrispCoder/Audio/Perfect_World_encoded.m4a',
          outputType: OutputType.audio,
        ).displayTitle,
        'Perfect_World_encoded.m4a',
      );
    });

    test('subtitle tasks are titled by the output artifact', () {
      expect(
        task(
          sourceName: 'movie.mp4',
          outputPath: '/docs/CrispCoder/Subtitles/movie_encoded.srt',
          outputType: OutputType.subtitle,
        ).displayTitle,
        'movie_encoded.srt',
      );
    });
  });
}
