import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/stream_information.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exceptions.dart';
import '../../core/utils/format_parsers.dart';
import '../../main.dart';
import '../models/media_info.dart';

/// Wraps FFprobe to extract typed source metadata.
class MediaProbeService {
  MediaProbeService(this._ref);
  final Ref _ref;

  /// Probes the given [path] and returns typed [MediaInfo].
  /// Throws [ProbeFailedException] on any error so callers can surface
  /// a user-friendly message.
  Future<MediaInfo> probe(String path) async {
    final log = _ref.read(loggerProvider);
    try {
      final session = await FFprobeKit.getMediaInformation(path);
      final info = session.getMediaInformation();
      if (info == null) {
        final rc = await session.getReturnCode();
        throw ProbeFailedException('ReturnCode: ${rc?.getValue()}');
      }

      final streams = info.getStreams();
      StreamInformation? video;
      StreamInformation? audio;
      final subtitles = <SubtitleTrack>[];

      // Track relative subtitle index separately from absolute stream index.
      // FFmpeg's `subtitles` filter `si` parameter counts only subtitle streams.
      int relativeSubIndex = 0;

      for (final s in streams) {
        final type = s.getType();
        if (video == null && type == 'video') {
          video = s;
        } else if (audio == null && type == 'audio') {
          audio = s;
        } else if (type == 'subtitle') {
          final props = s.getAllProperties();
          final tags = props?['tags'];
          final lang = tags is Map ? tags['language']?.toString() : null;

          subtitles.add(
            SubtitleTrack(
              index: int.tryParse(s.getIndex()?.toString() ?? '') ?? -1,
              subtitleStreamIndex: relativeSubIndex,
              language: lang,
              codec: s.getCodec(),
            ),
          );
          relativeSubIndex++;
        }
      }
      // Fallback to first stream if specific type not found
      if (streams.isNotEmpty) {
        video ??= streams.first;
        audio ??= streams.first;
      }

      final durationStr = info.getDuration();
      final duration = double.tryParse(durationStr ?? '');

      return MediaInfo(
        path: path,
        duration: duration == null ? null : Duration(seconds: duration.toInt()),
        width: int.tryParse(video?.getWidth()?.toString() ?? ''),
        height: int.tryParse(video?.getHeight()?.toString() ?? ''),
        videoCodec: video?.getCodec(),
        audioCodec: audio?.getCodec(),
        frameRate: FormatParsers.parseFramerate(video?.getAverageFrameRate()),
        bitrateBitsPerSec: int.tryParse(info.getBitrate() ?? ''),
        audioBitrateBitsPerSec: int.tryParse(audio?.getBitrate() ?? ''),
        container: info.getFormat(),
        subtitleTracks: subtitles,
      );
    } catch (e, st) {
      log.e('Probe failed for $path', error: e, stackTrace: st);
      if (e is ProbeFailedException) {
        rethrow;
      }
      throw ProbeFailedException(e.toString());
    }
  }
}

final mediaProbeServiceProvider = Provider<MediaProbeService>(
  (ref) => MediaProbeService(ref),
);
