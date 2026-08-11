import 'package:crispcoder/data/services/device_capability_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseMediacodecEncoders', () {
    test('extracts all three mediacodec encoders from -encoders output', () {
      const output = '''
Encoders:
 V..... = Video
 A..... = Audio
 S..... = Subtitle
 .F.... = Frame-level multithreading
 ..S... = Slice-level multithreading
 ...X.. = Codec is experimental
 ....B. = Supports draw_horiz_band
 .....D = Supports direct rendering method 1

 V....D av1_mediacodec            Android MediaCodec AV1 encoder (codec av1)
 V....D h264_mediacodec           Android MediaCodec H.264 encoder (codec h264)
 V....D hevc_mediacodec           Android MediaCodec HEVC encoder (codec hevc)
 V....D libx264                   libx264 H.264 / AVC / MPEG-4 AVC / MPEG-4 part 10 (codec h264)
''';
      expect(
        DeviceCapabilityService.parseMediacodecEncoders(output),
        {'h264_mediacodec', 'hevc_mediacodec', 'av1_mediacodec'},
      );
    });

    test('returns empty set when no mediacodec encoder is present', () {
      const output = '''
 V....D libx264  libx264 H.264 / AVC / MPEG-4 AVC / MPEG-4 part 10 (codec h264)
 V....D libx265  libx265 H.265 / HEVC (codec hevc)
''';
      expect(DeviceCapabilityService.parseMediacodecEncoders(output), isEmpty);
    });

    test('only reports encoders that actually exist', () {
      const output = '''
 V....D h264_mediacodec  Android MediaCodec H.264 encoder (codec h264)
''';
      final found = DeviceCapabilityService.parseMediacodecEncoders(output);
      expect(found, {'h264_mediacodec'});
      expect(found, isNot(contains('hevc_mediacodec')));
      expect(found, isNot(contains('av1_mediacodec')));
    });
  });
}
