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

  Future<MediaInfo> probe(String path) async {
    final log = _ref.read(loggerProvider);
    try {
      final session = await FFprobeKit.getMediaInformation(path);
      // getMediaInformation() is synchronous in this kit version
      final info = session.getMediaInformation();
      if (info == null) {
        final rc = await session.getReturnCode();
        throw ProbeFailedException('ReturnCode: ${rc?.getValue()}');
      }

      final streams = info.getStreams();
      StreamInformation? video;
      StreamInformation? audio;

      // Safely parse streams without instantiating abstract classes or triggering null-aware warnings
      for (final s in streams) {
        if (video == null && s.getType() == 'video') {
          video = s;
        }
        if (audio == null && s.getType() == 'audio') {
          audio = s;
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
