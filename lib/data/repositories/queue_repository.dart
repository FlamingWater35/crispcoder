import 'package:hive_ce/hive_ce.dart';

import '../../core/constants/app_constants.dart';
import '../models/encode_task.dart';

/// Persisted queue store. Every mutation is written through Hive so the
/// queue survives crashes; pending/running tasks are recovered on startup.
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
    // Any task marked running at exit time should reset to pending for resume
    for (final task in _box.values.toList()) {
      if (task.status == EncodeStatus.running ||
          task.status == EncodeStatus.paused) {
        await _box.put(task.id, task.copyWith(status: EncodeStatus.pending));
      }
    }
    _initialized = true;
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
