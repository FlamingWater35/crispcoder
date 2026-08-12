import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:hive_ce/hive_ce.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/hive_box_util.dart';
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
    // openHiveBox never throws: it falls back to an in-memory box if the
    // on-disk box cannot be opened, so `_box` is always assigned and the
    // queue provider can never hit LateInitializationError.
    _box = await openHiveBox<EncodeTask>(AppConstants.boxQueue);

    // Crash recovery: demote tasks that were running when the app died and
    // drop their partial output files. Each record is guarded individually —
    // a corrupt/truncated entry (or a future enum-index shift) must never
    // take down app startup; unreadable records are dropped.
    final ids = _box.keys.toList();
    for (final id in ids) {
      final EncodeTask? task;
      try {
        task = _box.get(id);
      } catch (_) {
        await _safeDelete(id);
        continue;
      }
      if (task == null) continue;
      try {
        if (task.status != EncodeStatus.running) continue;
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
      } catch (_) {
        // A record that fails to deserialize its fields (e.g. an out-of-range
        // enum index) cannot be recovered — drop it and keep going.
        await _safeDelete(id);
      }
    }

    _initialized = true;
  }

  /// Test hook: forget the in-memory state so [bootstrap] can run again
  /// against the same box (used by unit tests between cases).
  @visibleForTesting
  void resetForTesting() {
    _initialized = false;
  }

  Future<void> _safeDelete(dynamic id) async {
    try {
      await _box.delete(id);
    } catch (_) {
      // Best-effort cleanup
    }
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

  List<EncodeTask> get all {
    final tasks = <EncodeTask>[];
    for (final key in _box.keys) {
      try {
        final task = _box.get(key);
        if (task != null) tasks.add(task);
      } catch (_) {
        // Skip (and drop) corrupt records so the UI never crashes on them.
        _safeDelete(key);
      }
    }
    tasks.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return tasks;
  }

  EncodeTask? byId(String id) {
    try {
      return _box.get(id);
    } catch (_) {
      return null;
    }
  }

  Future<void> upsert(EncodeTask task) async {
    await _box.put(task.id, task);
  }

  Future<void> remove(String id) async {
    await _box.delete(id);
  }

  /// Removes all finished tasks: completed, cancelled, and failed. Pending,
  /// paused, and running tasks are kept.
  Future<void> clearCompleted() async {
    // Per-key guard, matching `all`: one corrupt record must not abort the
    // whole clear.
    final finished = <dynamic>[];
    for (final key in _box.keys) {
      try {
        final task = _box.get(key);
        if (task != null &&
            (task.status == EncodeStatus.completed ||
                task.status == EncodeStatus.cancelled ||
                task.status == EncodeStatus.failed)) {
          finished.add(key);
        }
      } catch (_) {
        await _safeDelete(key);
      }
    }
    for (final id in finished) {
      await _box.delete(id);
    }
  }
}
