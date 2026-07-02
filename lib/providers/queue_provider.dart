import 'dart:io';

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
import '../data/services/notification_service.dart';
import '../data/services/permission_service.dart';
import '../data/services/transcode_service.dart';
import 'active_encode_provider.dart';
import 'app_settings_provider.dart';
import 'device_capability_provider.dart';

/// Queue state + orchestration of the active encode.
/// Each mutation persists to Hive so the queue survives crashes.
final queueProvider = NotifierProvider<QueueNotifier, List<EncodeTask>>(
  QueueNotifier.new,
);

class QueueNotifier extends Notifier<List<EncodeTask>> {
  @override
  List<EncodeTask> build() {
    // Wire the notification "Cancel" button to cancelActive
    NotificationService.onCancelRequested = cancelActive;

    ref.listen<EncodeProgress?>(activeEncodeProvider, (_, p) {
      if (p != null) {
        ForegroundServiceWrapper.instance.updateText(
          'Progress: ${p.formattedPercent} • ${p.formattedSpeed} • ETA ${p.formattedEta}',
        );
        NotificationService.instance.showProgress(
          percent: p.percent.round(),
          content:
              '${p.formattedPercent} • ${p.formattedSpeed} • ETA ${p.formattedEta}',
        );
      }
    });

    return QueueRepository.instance.all;
  }

  /// Deletes a partial output file left by a cancelled or failed encode.
  /// Best-effort: silently ignores I/O errors.
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

  Future<void> enqueue(EncodeTask task) async {
    await QueueRepository.instance.upsert(task);
    state = QueueRepository.instance.all;
    if (state.where((t) => t.status == EncodeStatus.running).isEmpty) {
      startNext();
    }
  }

  Future<void> remove(String id) async {
    final task = state.firstWhereOrNull((t) => t.id == id);
    if (task != null && task.status == EncodeStatus.running) {
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
  /// On completion, saves to gallery (only if no custom output dir is set).
  /// On cancel/failure, deletes the partial output file.
  Future<void> startNext() async {
    EncodeTask? runningTask;
    try {
      if (ref.read(activeEncodeProvider) != null) return;

      final next = state.firstWhereOrNull(
        (t) => t.status == EncodeStatus.pending,
      );
      if (next == null) {
        await WakelockPlus.disable();
        await ForegroundServiceWrapper.instance.stop();
        await NotificationService.instance.cancelProgress();
        return;
      }

      try {
        await ref.read(permissionServiceProvider).requireNotifications();
      } catch (_) {}

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
      await NotificationService.instance.showProgress(
        percent: 0,
        content: 'Starting…',
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

      // Only save to gallery when no custom output directory is configured.
      // When a custom dir IS set, the file is already in the user's chosen
      // location — copying to gallery would create an unwanted duplicate.
      final settings = ref.read(appSettingsProvider);
      if (settings.outputDirectory == null) {
        await ref
            .read(galleryServiceProvider)
            .saveToGallery(finished.outputPath);
      }

      await NotificationService.instance.cancelProgress();
      await NotificationService.instance.showCompleted(
        next.sourceName ?? 'Video',
      );
    } on EncodeCancelledException {
      // Delete partial output so the user doesn't get a corrupt file
      if (runningTask != null) {
        await _deletePartialOutput(runningTask.outputPath);

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
      await NotificationService.instance.cancelProgress();
    } catch (e, st) {
      debugPrint('Error during startNext: $e\n$st');
      if (runningTask != null) {
        // Delete partial output from failed encode
        await _deletePartialOutput(runningTask.outputPath);

        final failed = runningTask.copyWith(
          status: EncodeStatus.failed,
          finishedAt: DateTime.now(),
          errorMessage: e.toString(),
        );
        await QueueRepository.instance.upsert(failed);
        await HistoryRepository.instance.add(failed);

        await NotificationService.instance.cancelProgress();
        await NotificationService.instance.showFailed(
          runningTask.sourceName ?? 'Video',
          e.toString().split('\n').first,
        );
      }
    } finally {
      ref.read(activeEncodeProvider.notifier).detach();
      state = QueueRepository.instance.all;
      if (state.any((t) => t.status == EncodeStatus.pending)) {
        await startNext();
      } else {
        await WakelockPlus.disable();
        await ForegroundServiceWrapper.instance.stop();
        await NotificationService.instance.cancelProgress();
      }
    }
  }

  Future<void> cancelActive() async {
    await ref.read(transcodeServiceProvider).cancel();
  }
}
