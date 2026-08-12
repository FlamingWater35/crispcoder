import 'package:crispcoder/data/models/media_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SubtitleTrack.isTextSubtitle', () {
    test('text subtitle codecs are recognized', () {
      for (final codec in [
        'subrip',
        'srt',
        'ass',
        'ssa',
        'mov_text',
        'webvtt',
        'text',
        'SubRip', // case-insensitive
      ]) {
        final track = SubtitleTrack(
          index: 0,
          subtitleStreamIndex: 0,
          codec: codec,
        );
        expect(track.isTextSubtitle, isTrue, reason: 'codec: $codec');
      }
    });

    test('bitmap subtitle codecs are not text', () {
      for (final codec in [
        'dvd_subtitle',
        'hdmv_pgs_subtitle',
        'pgssub',
        'xsub',
        'dvb_subtitle',
      ]) {
        final track = SubtitleTrack(
          index: 1,
          subtitleStreamIndex: 0,
          codec: codec,
        );
        expect(track.isTextSubtitle, isFalse, reason: 'codec: $codec');
      }
    });

    test('null codec is not treated as text', () {
      const track = SubtitleTrack(index: 0, subtitleStreamIndex: 0);
      expect(track.isTextSubtitle, isFalse);
    });
  });
}
