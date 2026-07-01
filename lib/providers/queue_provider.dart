import 'package:collection/collection.dart';
import 'package:crispcoder/core/errors/app_exceptions.dart';
import 'package:flutter/foundation.dart';
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
      // Fire and forget startNext so UI is not blocked while encoding
      startNext();
    }
  }

  Future<void> remove(String id) async {
    final task = state.firstWhereOrNull((t) => t.id == id);
    if (task != null && task.status == EncodeStatus.running) {
      // If it's running, remove from repo first, then cancel.
      // The startNext loop will see it's gone and not mark it as cancelled.
      await QueueRepository.instance.remove(id);
      await ref.read(transcodeServiceProvider).cancel();
    } else {
      await QueueRepository.instance.remove(id);
    }
    state = QueueRepository.instance.all;
  }

  Future<void> clearFinished() async {
    await QueueRepository.instance.clearCompleted();
    state = QueueRepository.instance.all;
  }

  /// Starts the next pending task. Idempotent: no-op if a task is running.
  Future<void> startNext() async {
    EncodeTask? runningTask;
    try {
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

      runningTask = next.copyWith(
        status: EncodeStatus.running,
        startedAt: DateTime.now(),
      );
      await QueueRepository.instance.upsert(runningTask);
      state = QueueRepository.instance.all;

      await WakelockPlus.enable();
      await ForegroundServiceWrapper.instance.start(
        title: 'Transcoding: ${next.sourceName ?? 'video'}',
        text: 'Starting…',
      );

      final session = await ref
          .read(transcodeServiceProvider)
          .start(
            task: runningTask,
            preset: next.preset,
            capability: await ref.read(deviceCapabilityProvider.future),
          );
      ref.read(activeEncodeProvider.notifier).attach(session);
      await session.completion;

      final finished = runningTask.copyWith(
        status: EncodeStatus.completed,
        finishedAt: DateTime.now(),
      );
      await QueueRepository.instance.upsert(finished);
      await HistoryRepository.instance.add(finished);

      await ref.read(galleryServiceProvider).saveToGallery(finished.outputPath);
    } on EncodeCancelledException {
      // If the task was cancelled, check if it still exists in the queue.
      // If it does, mark it as cancelled. If not, the user removed it.
      if (runningTask != null) {
        final existing = QueueRepository.instance.byId(runningTask.id);
        if (existing != null) {
          final cancelled = runningTask.copyWith(
            status: EncodeStatus.cancelled,
            finishedAt: DateTime.now(),
          );
          await QueueRepository.instance.upsert(cancelled);
          await HistoryRepository.instance.add(cancelled);
        }
      }
    } catch (e, st) {
      debugPrint('Error during startNext: $e\n$st');
      if (runningTask != null) {
        final failed = runningTask.copyWith(
          status: EncodeStatus.failed,
          finishedAt: DateTime.now(),
          errorMessage: e.toString(),
        );
        await QueueRepository.instance.upsert(failed);
        await HistoryRepository.instance.add(failed);
      }
    } finally {
      ref.read(activeEncodeProvider.notifier).detach();
      state = QueueRepository.instance.all;
      // Continue processing the queue if there are pending tasks
      if (state.any((t) => t.status == EncodeStatus.pending)) {
        await startNext();
      } else {
        await WakelockPlus.disable();
        await ForegroundServiceWrapper.instance.stop();
      }
    }
  }

  Future<void> cancelActive() async {
    await ref.read(transcodeServiceProvider).cancel();
  }
}
