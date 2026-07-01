import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../data/models/encode_progress.dart';
import '../data/models/encode_task.dart';
import '../data/repositories/history_repository.dart';
import '../data/repositories/queue_repository.dart';
import '../data/services/foreground_service_wrapper.dart';
import '../data/services/gallery_service.dart';
import '../data/services/transcode_service.dart';
import 'active_encode_provider.dart';
import 'device_capability_provider.dart';

/// Queue state + orchestration of the active encode.
/// Each mutation persists to Hive so the queue survives crashes.
final queueProvider = NotifierProvider<QueueNotifier, List<EncodeTask>>(
  QueueNotifier.new,
);

class QueueNotifier extends Notifier<List<EncodeTask>> {
  @override
  List<EncodeTask> build() {
    ref.listen<EncodeProgress?>(activeEncodeProvider, (_, p) {
      if (p != null) {
        ForegroundServiceWrapper.instance.updateText(
          '${p.formattedPercent} • ${p.formattedSpeed} • ETA ${p.formattedEta}',
        );
      }
    });

    return QueueRepository.instance.all;
  }

  Future<void> enqueue(EncodeTask task) async {
    await QueueRepository.instance.upsert(task);
    state = QueueRepository.instance.all;
    if (state.where((t) => t.status == EncodeStatus.running).isEmpty) {
      await startNext();
    }
  }

  Future<void> remove(String id) async {
    if (state.any((t) => t.id == id && t.status == EncodeStatus.running)) {
      await ref.read(transcodeServiceProvider).cancel();
    }
    await QueueRepository.instance.remove(id);
    state = QueueRepository.instance.all;
  }

  Future<void> clearFinished() async {
    await QueueRepository.instance.clearCompleted();
    state = QueueRepository.instance.all;
  }

  /// Starts the next pending task. Idempotent: no-op if a task is running.
  Future<void> startNext() async {
    if (ref.read(activeEncodeProvider) != null) {
      return;
    }

    final next = state.firstWhereOrNull(
      (t) => t.status == EncodeStatus.pending,
    );
    if (next == null) {
      await WakelockPlus.disable();
      await ForegroundServiceWrapper.instance.stop();
      return;
    }

    final preset = next.preset; // Use embedded preset directly
    final cap = await ref.read(deviceCapabilityProvider.future);
    final svc = ref.read(transcodeServiceProvider);

    final running = next.copyWith(
      status: EncodeStatus.running,
      startedAt: DateTime.now(),
    );
    await QueueRepository.instance.upsert(running);
    state = QueueRepository.instance.all;

    await WakelockPlus.enable();
    await ForegroundServiceWrapper.instance.start(
      title: 'Transcoding: ${next.sourceName ?? 'video'}',
      text: 'Starting…',
    );

    try {
      final session = await svc.start(
        task: running,
        preset: preset,
        capability: cap,
      );
      ref.read(activeEncodeProvider.notifier).attach(session);
      await session.completion;

      final finished = running.copyWith(
        status: EncodeStatus.completed,
        finishedAt: DateTime.now(),
      );
      await QueueRepository.instance.upsert(finished);
      await HistoryRepository.instance.add(finished);

      await ref.read(galleryServiceProvider).saveToGallery(finished.outputPath);
    } catch (e) {
      final failed = running.copyWith(
        status: EncodeStatus.failed,
        finishedAt: DateTime.now(),
        errorMessage: e.toString(),
      );
      await QueueRepository.instance.upsert(failed);
      await HistoryRepository.instance.add(failed);
    } finally {
      ref.read(activeEncodeProvider.notifier).detach();
      state = QueueRepository.instance.all;
      await startNext();
    }
  }

  Future<void> cancelActive() async {
    await ref.read(transcodeServiceProvider).cancel();
  }
}
