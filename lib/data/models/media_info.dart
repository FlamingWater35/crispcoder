/// Lightweight probed metadata for a source media file.
class MediaInfo {
  final String path;
  final Duration? duration;
  final int? width;
  final int? height;
  final String? videoCodec;
  final String? audioCodec;
  final double? frameRate;
  final int? bitrateBitsPerSec;
  final String? container;

  const MediaInfo({
    required this.path,
    this.duration,
    this.width,
    this.height,
    this.videoCodec,
    this.audioCodec,
    this.frameRate,
    this.bitrateBitsPerSec,
    this.container,
  });

  String get resolutionLabel {
    if (width == null || height == null) {
      return 'Unknown';
    }
    return '${width}x$height';
  }

  String get durationLabel {
    if (duration == null) {
      return '—';
    }
    final s = duration!.inSeconds;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    return h > 0
        ? '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}'
        : '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }
}
