import 'package:hive_ce/hive_ce.dart';

/// Video codec selection. `copy` bypasses re-encoding (passthrough).
enum VideoCodec { h264, hevc, av1, copy }

/// Audio codec selection.
enum AudioCodec { aac, opus, mp3, ac3, copy }

/// Output container format.
enum ContainerFormat { mp4, mkv, webm }

/// Encoder preference: hardware (MediaCodec), software (libx*), or auto.
enum EncoderPreference { hardware, software, auto }

/// Handbrake-style preset describing the full encode pipeline.
class TranscodePreset {
  final String id;
  final String name;
  final String category;
  final VideoCodec videoCodec;
  final int? crf;
  final int? videoBitrate;
  final String? resolution;
  final int? framerate;
  final AudioCodec audioCodec;
  final int audioBitrate;
  final ContainerFormat container;
  final EncoderPreference encoderPref;
  final String? filterChain;
  final bool faststart;
  final bool twoPass;
  final bool isBuiltIn;

  // New Editing Fields
  final bool removeAudio;
  final int?
  burnSubtitleIndex; // Relative subtitle stream index (0-based) for FFmpeg's `subtitles` filter `si` parameter
  final String? startTime; // e.g., "00:01:30"
  final String? endTime; // e.g., "00:05:00"

  const TranscodePreset({
    required this.id,
    required this.name,
    required this.category,
    required this.videoCodec,
    this.crf,
    this.videoBitrate,
    this.resolution,
    this.framerate,
    required this.audioCodec,
    required this.audioBitrate,
    required this.container,
    this.encoderPref = EncoderPreference.auto,
    this.filterChain,
    this.faststart = true,
    this.twoPass = false,
    this.isBuiltIn = false,
    this.removeAudio = false,
    this.burnSubtitleIndex,
    this.startTime,
    this.endTime,
  });

  TranscodePreset copyWith({
    String? id,
    String? name,
    String? category,
    VideoCodec? videoCodec,
    int? crf,
    int? videoBitrate,
    String? resolution,
    int? framerate,
    AudioCodec? audioCodec,
    int? audioBitrate,
    ContainerFormat? container,
    EncoderPreference? encoderPref,
    String? filterChain,
    bool? faststart,
    bool? twoPass,
    bool? isBuiltIn,
    bool? removeAudio,
    int? burnSubtitleIndex,
    String? startTime,
    String? endTime,
  }) {
    return TranscodePreset(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      videoCodec: videoCodec ?? this.videoCodec,
      crf: crf ?? this.crf,
      videoBitrate: videoBitrate ?? this.videoBitrate,
      resolution: resolution ?? this.resolution,
      framerate: framerate ?? this.framerate,
      audioCodec: audioCodec ?? this.audioCodec,
      audioBitrate: audioBitrate ?? this.audioBitrate,
      container: container ?? this.container,
      encoderPref: encoderPref ?? this.encoderPref,
      filterChain: filterChain ?? this.filterChain,
      faststart: faststart ?? this.faststart,
      twoPass: twoPass ?? this.twoPass,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      removeAudio: removeAudio ?? this.removeAudio,
      burnSubtitleIndex: burnSubtitleIndex ?? this.burnSubtitleIndex,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
    );
  }

  String get fileExtension => switch (container) {
    ContainerFormat.mp4 => 'mp4',
    ContainerFormat.mkv => 'mkv',
    ContainerFormat.webm => 'webm',
  };
}

/// Manual Hive adapter (avoids build_runner dependency at app start).
class TranscodePresetAdapter extends TypeAdapter<TranscodePreset> {
  @override
  final int typeId = 1;

  @override
  TranscodePreset read(BinaryReader r) {
    return TranscodePreset(
      id: r.readString(),
      name: r.readString(),
      category: r.readString(),
      videoCodec: VideoCodec.values[r.readByte()],
      crf: r.readByte() == 1 ? r.readInt() : null,
      videoBitrate: r.readByte() == 1 ? r.readInt() : null,
      resolution: r.readByte() == 1 ? r.readString() : null,
      framerate: r.readByte() == 1 ? r.readInt() : null,
      audioCodec: AudioCodec.values[r.readByte()],
      audioBitrate: r.readInt(),
      container: ContainerFormat.values[r.readByte()],
      encoderPref: EncoderPreference.values[r.readByte()],
      filterChain: r.readByte() == 1 ? r.readString() : null,
      faststart: r.readBool(),
      twoPass: r.readBool(),
      isBuiltIn: r.readBool(),
      removeAudio: r.readBool(),
      burnSubtitleIndex: r.readByte() == 1 ? r.readInt() : null,
      startTime: r.readByte() == 1 ? r.readString() : null,
      endTime: r.readByte() == 1 ? r.readString() : null,
    );
  }

  @override
  void write(BinaryWriter w, TranscodePreset p) {
    w.writeString(p.id);
    w.writeString(p.name);
    w.writeString(p.category);
    w.writeByte(p.videoCodec.index);
    _writeNullableInt(w, p.crf);
    _writeNullableInt(w, p.videoBitrate);
    _writeNullableString(w, p.resolution);
    _writeNullableInt(w, p.framerate);
    w.writeByte(p.audioCodec.index);
    w.writeInt(p.audioBitrate);
    w.writeByte(p.container.index);
    w.writeByte(p.encoderPref.index);
    _writeNullableString(w, p.filterChain);
    w.writeBool(p.faststart);
    w.writeBool(p.twoPass);
    w.writeBool(p.isBuiltIn);
    w.writeBool(p.removeAudio);
    _writeNullableInt(w, p.burnSubtitleIndex);
    _writeNullableString(w, p.startTime);
    _writeNullableString(w, p.endTime);
  }

  static void _writeNullableInt(BinaryWriter w, int? v) {
    if (v == null) {
      w.writeByte(0);
    } else {
      w.writeByte(1);
      w.writeInt(v);
    }
  }

  static void _writeNullableString(BinaryWriter w, String? v) {
    if (v == null) {
      w.writeByte(0);
    } else {
      w.writeByte(1);
      w.writeString(v);
    }
  }
}
