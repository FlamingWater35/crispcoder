import 'package:hive_ce/hive_ce.dart';

import 'transcode_preset.dart';

/// Lifecycle states for an encode task. Persisted for crash recovery.
enum EncodeStatus { pending, running, paused, completed, failed, cancelled }

/// Represents a single transcode job in the queue.
class EncodeTask {
  final String id;
  final String sourcePath;
  final String? sourceName;
  final String outputPath;
  final TranscodePreset preset; // Embedded preset for custom configurations
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final EncodeStatus status;
  final String? errorMessage;
  final double totalDurationSeconds;

  EncodeTask({
    required this.id,
    required this.sourcePath,
    this.sourceName,
    required this.outputPath,
    required this.preset,
    required this.createdAt,
    this.startedAt,
    this.finishedAt,
    this.status = EncodeStatus.pending,
    this.errorMessage,
    this.totalDurationSeconds = 0,
  });

  EncodeTask copyWith({
    String? id,
    String? sourcePath,
    String? sourceName,
    String? outputPath,
    TranscodePreset? preset,
    DateTime? createdAt,
    DateTime? startedAt,
    DateTime? finishedAt,
    EncodeStatus? status,
    String? errorMessage,
    double? totalDurationSeconds,
  }) {
    return EncodeTask(
      id: id ?? this.id,
      sourcePath: sourcePath ?? this.sourcePath,
      sourceName: sourceName ?? this.sourceName,
      outputPath: outputPath ?? this.outputPath,
      preset: preset ?? this.preset,
      createdAt: createdAt ?? this.createdAt,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      totalDurationSeconds: totalDurationSeconds ?? this.totalDurationSeconds,
    );
  }
}

class EncodeTaskAdapter extends TypeAdapter<EncodeTask> {
  @override
  final int typeId = 2;

  @override
  EncodeTask read(BinaryReader r) {
    return EncodeTask(
      id: r.readString(),
      sourcePath: r.readString(),
      sourceName: r.readByte() == 1 ? r.readString() : null,
      outputPath: r.readString(),
      preset: r.read() as TranscodePreset,
      createdAt: DateTime.fromMillisecondsSinceEpoch(r.readInt()),
      startedAt: r.readByte() == 1
          ? DateTime.fromMillisecondsSinceEpoch(r.readInt())
          : null,
      finishedAt: r.readByte() == 1
          ? DateTime.fromMillisecondsSinceEpoch(r.readInt())
          : null,
      status: EncodeStatus.values[r.readByte()],
      errorMessage: r.readByte() == 1 ? r.readString() : null,
      totalDurationSeconds: r.readDouble(),
    );
  }

  @override
  void write(BinaryWriter w, EncodeTask t) {
    w.writeString(t.id);
    w.writeString(t.sourcePath);
    if (t.sourceName == null) {
      w.writeByte(0);
    } else {
      w.writeByte(1);
      w.writeString(t.sourceName!);
    }
    w.writeString(t.outputPath);
    w.write(t.preset); // Hive resolves the adapter automatically
    w.writeInt(t.createdAt.millisecondsSinceEpoch);
    if (t.startedAt == null) {
      w.writeByte(0);
    } else {
      w.writeByte(1);
      w.writeInt(t.startedAt!.millisecondsSinceEpoch);
    }
    if (t.finishedAt == null) {
      w.writeByte(0);
    } else {
      w.writeByte(1);
      w.writeInt(t.finishedAt!.millisecondsSinceEpoch);
    }
    w.writeByte(t.status.index);
    if (t.errorMessage == null) {
      w.writeByte(0);
    } else {
      w.writeByte(1);
      w.writeString(t.errorMessage!);
    }
    w.writeDouble(t.totalDurationSeconds);
  }
}

class EncodeStatusAdapter extends TypeAdapter<EncodeStatus> {
  @override
  final int typeId = 3;

  @override
  EncodeStatus read(BinaryReader r) => EncodeStatus.values[r.readByte()];

  @override
  void write(BinaryWriter w, EncodeStatus obj) => w.writeByte(obj.index);
}
