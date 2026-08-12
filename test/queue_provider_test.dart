import 'dart:async';
import 'dart:io';

import 'package:crispcoder/data/models/device_capability.dart';
import 'package:crispcoder/data/models/encode_progress.dart';
import 'package:crispcoder/data/models/encode_task.dart';
import 'package:crispcoder/data/models/transcode_preset.dart';
import 'package:crispcoder/data/repositories/history_repository.dart';
import 'package:crispcoder/data/repositories/queue_repository.dart';
import 'package:crispcoder/data/services/transcode_service.dart';
import 'package:crispcoder/providers/queue_provider.dart';
import 'package:ffmpeg_kit_flutter_new/abstract_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

/// Records `start()` invocations instead of launching real FFmpeg. The
/// session's completion future is left pending so the test can observe the
/// startup window (where the race used to live) without running the whole
/// post-encode publish flow.
class _FakeTranscodeService extends TranscodeService {
  _FakeTranscodeService(super.ref);

  int startCalls = 0;
  final Completer<void> completion = Completer<void>();

  @override
  Future<ActiveSession> start({
    required EncodeTask task,
    required TranscodePreset preset,
    required DeviceCapability capability,
  }) async {
    startCalls++;
    final session = AbstractSession.createFFmpegSessionFromMap({
      'sessionId': 1,
      'command': '-y -i /tmp/in.mp4',
    });
    return ActiveSession(
      taskId: task.id,
      session: session,
      progress: const Stream<EncodeProgress>.empty(),
      completion: completion.future,
    );
  }
}

class _FakeWakelockPlatform extends WakelockPlusPlatformInterface {
  @override
  Future<bool> get enabled async => false;

  @override
  Future<void> toggle({required bool enable}) async {}
}

EncodeTask _task(String id) {
  return EncodeTask(
    id: id,
    sourcePath: '/tmp/$id.mp4',
    sourceName: '$id.mp4',
    outputPath: '/tmp/out_$id.mp4',
    preset: TranscodePreset(
      id: 'p',
      name: 'P',
      category: 'Test',
      videoCodec: VideoCodec.h264,
      crf: 23,
      audioCodec: AudioCodec.aac,
      audioBitrate: 160,
      container: ContainerFormat.mp4,
    ),
    createdAt: DateTime(2024, 1, 1),
    totalDurationSeconds: 60,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('crispcoder_queue_provider');
    Hive.init(tempDir.path);
    Hive.registerAdapter(TranscodePresetAdapter());
    Hive.registerAdapter(EncodeTaskAdapter());
    Hive.registerAdapter(EncodeStatusAdapter());
    wakelockPlusPlatformInstance = _FakeWakelockPlatform();
    await HistoryRepository.instance.bootstrap();
  });

  tearDownAll(() async {
    await Hive.deleteFromDisk();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    await Hive.deleteBoxFromDisk('queue');
    QueueRepository.instance.resetForTesting();
    await QueueRepository.instance.bootstrap();
  });

  test('two enqueues in the same tick start only one encode', () async {
    final container = ProviderContainer(
      overrides: [
        transcodeServiceProvider.overrideWith(
          (ref) => _FakeTranscodeService(ref),
        ),
      ],
    );
    addTearDown(container.dispose);
    final fake = container.read(transcodeServiceProvider) as _FakeTranscodeService;

    final notifier = container.read(queueProvider.notifier);

    // Fire both without awaiting: `enqueue()` calls startNext() without
    // awaiting it, so two calls in the same tick hit the single-flight
    // window where `activeEncodeProvider` is still null.
    final first = notifier.enqueue(_task('a'));
    final second = notifier.enqueue(_task('b'));
    await Future.wait([first, second]);

    // Give the (fire-and-forget) first startNext time to reach fake.start().
    // Real async: notification permission (MissingPluginException, swallowed),
    // WakelockPlus.enable, foreground service, capability detection, then
    // transcodeService.start.
    for (var i = 0; i < 20 && fake.startCalls == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    // The single-flight guard must have blocked the second startNext.
    expect(fake.startCalls, 1);

    // Exactly one task was promoted to running; the other stays pending.
    final tasks = QueueRepository.instance.all;
    expect(
      tasks.where((t) => t.status == EncodeStatus.running).length,
      1,
    );
    expect(tasks.where((t) => t.status == EncodeStatus.pending).length, 1);
  });
}
