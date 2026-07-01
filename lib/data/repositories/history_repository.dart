import 'package:hive_ce/hive_ce.dart';

import '../../core/constants/app_constants.dart';
import '../models/encode_task.dart';

/// Append-only history of finished encodes (success or failure).
class HistoryRepository {
  HistoryRepository._();
  static final HistoryRepository instance = HistoryRepository._();

  late Box<EncodeTask> _box;
  bool _initialized = false;

  Future<void> bootstrap() async {
    if (_initialized) {
      return;
    }
    _box = await Hive.openBox<EncodeTask>(AppConstants.boxHistory);
    _initialized = true;
  }

  List<EncodeTask> get all => _box.values.toList()
    ..sort(
      (a, b) =>
          (b.finishedAt ?? b.createdAt).compareTo(a.finishedAt ?? a.createdAt),
    );

  Future<void> add(EncodeTask task) async {
    await _box.put(task.id, task);
  }

  Future<void> clear() async {
    await _box.clear();
  }
}
