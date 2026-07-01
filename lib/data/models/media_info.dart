/// Lightweight representation of a subtitle stream.
class SubtitleTrack {
  /// Absolute stream index as reported by FFprobe (e.g., 0, 1, 2).
  /// Used only for display so the label matches FFprobe output.
  final int index;

  /// Zero-based index among subtitle streams only (0, 1, 2, …).
  /// Passed to FFmpeg's `subtitles` filter `si` parameter, which
  /// counts only streams of type AVMEDIA_TYPE_SUBTITLE.
  final int subtitleStreamIndex;

  final String? language;
  final String? codec;

  const SubtitleTrack({
    required this.index,
    required this.subtitleStreamIndex,
    this.language,
    this.codec,
  });

  /// Human-readable label using the absolute index for familiarity.
  String get label {
    final lang = language ?? 'Unknown';
    final cod = codec ?? 'sub';
    return 'Track $index ($lang, $cod)';
  }
}

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
  final int? audioBitrateBitsPerSec;
  final String? container;
  final List<SubtitleTrack> subtitleTracks;

  const MediaInfo({
    required this.path,
    this.duration,
    this.width,
    this.height,
    this.videoCodec,
    this.audioCodec,
    this.frameRate,
    this.bitrateBitsPerSec,
    this.audioBitrateBitsPerSec,
    this.container,
    this.subtitleTracks = const [],
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
