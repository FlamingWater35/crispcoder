import 'dart:io';

import 'package:collection/collection.dart';
import 'package:crispcoder/core/errors/app_exceptions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../data/models/encode_progress.dart';
import '../data/models/encode_task.dart';
import '../data/models/transcode_preset.dart';
import '../data/repositories/history_repository.dart';
import '../data/repositories/queue_repository.dart';
import '../data/services/foreground_service_wrapper.dart';
import '../data/services/gallery_service.dart';
import '../data/services/notification_service.dart';
import '../data/services/permission_service.dart';
import '../data/services/transcode_service.dart';
import '../main.dart';
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

  /// Starts the next pending task if one exists and nothing is running.
  ///
  /// This is the manual entry point to pick up a queue that survived an app
  /// restart (persisted tasks are demoted to `pending` on bootstrap but are
  /// never auto-started). No-op when a task is already running or the queue
  /// has no pending work.
  Future<void> resume() async {
    final hasPending = state.any((t) => t.status == EncodeStatus.pending);
    if (!hasPending) return;
    if (ref.read(activeEncodeProvider) != null) return;
    await startNext();
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
        title: 'Transcoding: ${next.displayTitle}',
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

      // All outputs are published to DCIM/Videolation when no custom output
      // directory is configured. The platform channel uses MediaStore so
      // video, audio AND subtitle files land in the same user-visible folder
      // (audio/subtitle must never go through Gal.putVideo, which would
      // register them as video/gallery items). The result is persisted on the
      // task so the queue tile can display an accurate "Saved to DCIM" label
      // instead of guessing from the output path.
      final finished = runningTask.copyWith(
        status: EncodeStatus.completed,
        finishedAt: DateTime.now(),
      );
      final settings = ref.read(appSettingsProvider);
      var savedToGallery = false;
      String? publishedUri;
      if (settings.outputDirectory == null) {
        // Audio outputs are inserted into MediaStore.Audio.Media, which some
        // OEMs reject on API 33+ without READ_MEDIA_AUDIO. Request it right
        // before the publish (lazily, so boot never shows an extra dialog).
        // Best-effort: a denial only leaves the output in app storage.
        if (next.preset.outputType == OutputType.audio) {
          await ref.read(permissionServiceProvider).requireAudioRead();
        }
        // saveToDCIM returns the MediaStore URI (content://…) on success.
        // On failure it returns null after logging the real exception.
        publishedUri = await ref
            .read(galleryServiceProvider)
            .saveToDCIM(
              path: finished.outputPath,
              outputType: next.preset.outputType,
              displayName: p.basename(finished.outputPath),
            );
        savedToGallery = publishedUri != null;
        if (publishedUri == null) {
          ref.read(loggerProvider).w(
            'saveToDCIM returned null for ${finished.outputPath} — '
            'the output stays in app-private storage and no DCIM/Videolation '
            'entry was created. Check Logcat for the underlying exception.',
          );
        } else {
          // The file now lives in MediaStore (DCIM/Videolation). Delete the
          // private copy so it does not linger in app storage forever — the
          // "(1)" duplicate names and the storage leak both come from these
          // undeleted copies colliding with the next encode's uniqueOutputPath.
          await _deletePartialOutput(finished.outputPath);
        }
      }
      final persisted = finished.copyWith(
        savedToGallery: savedToGallery,
        publishedUri: publishedUri,
      );
      await QueueRepository.instance.upsert(persisted);
      await HistoryRepository.instance.add(persisted);

      await NotificationService.instance.cancelProgress();
      await NotificationService.instance.showCompleted(
        id: next.id,
        title: next.displayTitle,
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
          id: runningTask.id,
          title: runningTask.displayTitle,
          error: e.toString().split('\n').first,
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
