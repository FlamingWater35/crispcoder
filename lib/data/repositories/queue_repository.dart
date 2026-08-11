import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:hive_ce/hive_ce.dart';

import '../../core/constants/app_constants.dart';
import '../models/encode_task.dart';

/// Persisted queue store, restored on app startup.
///
/// Tasks survive process death: entries are kept and re-surfaced so the
/// queue is not lost on restart. Tasks that were mid-flight (`running`) when
/// the app died are demoted back to `pending` so they can be retried, and
/// their partial output files are deleted to avoid shipping truncated files.
class QueueRepository {
  QueueRepository._();
  static final QueueRepository instance = QueueRepository._();

  late Box<EncodeTask> _box;
  bool _initialized = false;

  Future<void> bootstrap() async {
    if (_initialized) {
      return;
    }
    _box = await Hive.openBox<EncodeTask>(AppConstants.boxQueue);

    // Crash recovery: demote tasks that were running when the app died and
    // drop their partial output files.
    final ids = _box.keys.toList();
    for (final id in ids) {
      final task = _box.get(id);
      if (task == null || task.status != EncodeStatus.running) continue;
      await _deletePartialOutput(task.outputPath);
      // Build the demoted task explicitly: copyWith cannot clear the
      // timestamps because its nullable params use `?? this.field`.
      await _box.put(
        task.id,
        EncodeTask(
          id: task.id,
          sourcePath: task.sourcePath,
          sourceName: task.sourceName,
          outputPath: task.outputPath,
          preset: task.preset,
          createdAt: task.createdAt,
          startedAt: null,
          finishedAt: null,
          status: EncodeStatus.pending,
          errorMessage: null,
          totalDurationSeconds: task.totalDurationSeconds,
        ),
      );
    }

    _initialized = true;
  }

  /// Test hook: forget the in-memory state so [bootstrap] can run again
  /// against the same box (used by unit tests between cases).
  @visibleForTesting
  void resetForTesting() {
    _initialized = false;
  }

  /// Best-effort removal of a partial output file left by a crashed encode.
  Future<void> _deletePartialOutput(String outputPath) async {
    try {
      final file = File(outputPath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Best-effort cleanup
    }
  }

  List<EncodeTask> get all =>
      _box.values.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  EncodeTask? byId(String id) => _box.get(id);

  Future<void> upsert(EncodeTask task) async {
    await _box.put(task.id, task);
  }

  Future<void> remove(String id) async {
    await _box.delete(id);
  }

  Future<void> clearCompleted() async {
    final completed = _box.values
        .where(
          (t) =>
              t.status == EncodeStatus.completed ||
              t.status == EncodeStatus.cancelled,
        )
        .map((t) => t.id)
        .toList();
    for (final id in completed) {
      await _box.delete(id);
    }
  }
}
