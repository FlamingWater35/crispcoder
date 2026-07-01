import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exceptions.dart';
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
      final info = await session.getMediaInformation();
      if (info == null) {
        final rc = await session.getReturnCode();
        throw ProbeFailedException('ReturnCode: ${rc?.getValue()}');
      }

      final streams = info.getStreams() ?? [];
      final video = streams.firstWhere(
        (s) => s.getType() == 'video',
        orElse: () => streams.isNotEmpty ? streams.first : Stream(),
      );

      final durationStr = info.getDuration();
      final duration = double.tryParse(durationStr ?? '');

      return MediaInfo(
        path: path,
        duration: duration == null ? null : Duration(seconds: duration.toInt()),
        width: int.tryParse(video.getWidth()?.toString() ?? ''),
        height: int.tryParse(video.getHeight()?.toString() ?? ''),
        videoCodec: video.getCodec(),
        audioCodec: streams
            .firstWhere(
              (s) => s.getType() == 'audio',
              orElse: () => streams.isNotEmpty ? streams.first : Stream(),
            )
            .getCodec(),
        frameRate: double.tryParse(video.getAverageFrameRate() ?? ''),
        bitrateBitsPerSec: int.tryParse(info.getBitrate() ?? ''),
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
