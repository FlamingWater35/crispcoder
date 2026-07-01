import 'package:hive_ce/hive_ce.dart';

import '../../core/constants/app_constants.dart';
import '../models/encode_task.dart';

/// Persisted queue store. Cleared on app startup to remove stale operations.
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

    // Remove queued operations after relaunching the app to start fresh.
    await _box.clear();

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
