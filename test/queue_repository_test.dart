import 'dart:io';

import 'package:crispcoder/core/constants/app_constants.dart';
import 'package:crispcoder/core/utils/hive_box_util.dart';
import 'package:crispcoder/data/models/encode_task.dart';
import 'package:crispcoder/data/models/transcode_preset.dart';
import 'package:crispcoder/data/repositories/queue_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('crispcoder_queue_test');
    Hive.init(tempDir.path);
    Hive.registerAdapter(TranscodePresetAdapter());
    Hive.registerAdapter(EncodeTaskAdapter());
    Hive.registerAdapter(EncodeStatusAdapter());
  });

  tearDownAll(() async {
    await Hive.deleteFromDisk();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    // Fresh box per test
    await Hive.deleteBoxFromDisk(AppConstants.boxQueue);
    QueueRepository.instance.resetForTesting();
  });

  EncodeTask task({
    required String id,
    EncodeStatus status = EncodeStatus.pending,
    String outputPath = '/tmp/out.mp4',
  }) {
    return EncodeTask(
      id: id,
      sourcePath: '/tmp/in.mp4',
      sourceName: 'in.mp4',
      outputPath: outputPath,
      preset: const TranscodePreset(
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
      status: status,
      startedAt: status == EncodeStatus.running ? DateTime(2024, 1, 1) : null,
      totalDurationSeconds: 60,
    );
  }

  test('bootstrap restores pending and completed tasks (no clear)', () async {
    final repo = QueueRepository.instance;
    await repo.bootstrap();

    await repo.upsert(task(id: 'pending'));
    await repo.upsert(task(id: 'done', status: EncodeStatus.completed));
    expect(repo.all.length, 2);

    // Simulate restart: re-run bootstrap with the same box.
    repo.resetForTesting();
    await repo.bootstrap();

    expect(repo.all.length, 2);
    expect(repo.byId('pending'), isNotNull);
    expect(repo.byId('done')?.status, EncodeStatus.completed);
  });

  test('bootstrap demotes stale running tasks to pending', () async {
    final repo = QueueRepository.instance;
    await repo.bootstrap();

    await repo.upsert(task(id: 'running', status: EncodeStatus.running));
    expect(repo.byId('running')?.status, EncodeStatus.running);

    // Simulate app restart after a crash mid-encode.
    repo.resetForTesting();
    await repo.bootstrap();

    final restored = repo.byId('running');
    expect(restored, isNotNull);
    expect(restored?.status, EncodeStatus.pending);
    expect(restored?.startedAt, isNull);
  });

  test('clearCompleted removes completed, cancelled, and failed tasks', () async {
    final repo = QueueRepository.instance;
    await repo.bootstrap();

    await repo.upsert(task(id: 'pending', status: EncodeStatus.pending));
    await repo.upsert(task(id: 'done', status: EncodeStatus.completed));
    await repo.upsert(task(id: 'cancelled', status: EncodeStatus.cancelled));
    await repo.upsert(task(id: 'failed', status: EncodeStatus.failed));

    await repo.clearCompleted();

    // Finished tasks are gone; pending survives.
    expect(repo.byId('done'), isNull);
    expect(repo.byId('cancelled'), isNull);
    expect(repo.byId('failed'), isNull);
    expect(repo.byId('pending'), isNotNull);
    expect(repo.all.length, 1);
  });

  test('clearCompleted keeps paused and running tasks', () async {
    final repo = QueueRepository.instance;
    await repo.bootstrap();

    await repo.upsert(task(id: 'paused', status: EncodeStatus.paused));
    await repo.upsert(task(id: 'running', status: EncodeStatus.running));
    await repo.upsert(task(id: 'failed', status: EncodeStatus.failed));

    await repo.clearCompleted();

    expect(repo.byId('paused'), isNotNull);
    expect(repo.byId('running'), isNotNull);
    expect(repo.byId('failed'), isNull);
  });

  test('bootstrap deletes partial output of crashed running tasks', () async {
    final repo = QueueRepository.instance;
    await repo.bootstrap();

    // Create a fake partial output file to simulate an interrupted encode.
    final partial = File(p.join(tempDir.path, 'partial.mp4'));
    await partial.writeAsString('partial');

    await repo.upsert(
      task(
        id: 'crashed',
        status: EncodeStatus.running,
        outputPath: partial.path,
      ),
    );

    repo.resetForTesting();
    await repo.bootstrap();

    expect(await partial.exists(), isFalse);
    expect(repo.byId('crashed')?.status, EncodeStatus.pending);
  });

  test('corrupt record does not crash bootstrap or all', () async {
    final repo = QueueRepository.instance;
    await repo.bootstrap();

    // Seed one good record, then corrupt the box file on disk directly
    // (a truncated/corrupt record is a disk-level condition Hive can't
    // express through its typed API). Closing the box first releases the
    // file lock so the corruption is picked up on the next open.
    await repo.upsert(task(id: 'good'));
    final box = Hive.box<EncodeTask>(AppConstants.boxQueue);
    await box.close();
    final hiveFile = File(p.join(tempDir.path, '${AppConstants.boxQueue}.hive'));
    await hiveFile.writeAsString('garbage not a hive file');

    repo.resetForTesting();
    // Must not throw.
    await repo.bootstrap();

    final all = repo.all;
    expect(all, isEmpty); // corrupt file → nothing recoverable, no crash
  });

  test('openHiveBox falls back to in-memory when the disk box cannot open',
      () async {
    // Make the box file unopenable by replacing it with a directory of the
    // same name. Hive's crash recovery can repair a truncated file, but it
    // cannot open a path that is a directory — this forces the in-memory
    // fallback path in openHiveBox.
    final settingsPath = p.join(tempDir.path, '${AppConstants.boxSettings}.hive');
    final blocker = Directory(settingsPath);
    await blocker.create(recursive: true);

    // The helper must not throw and must return a usable box.
    final box = await openHiveBox<EncodeTask>(AppConstants.boxSettings);
    expect(box, isNotNull);
    await box.put('k', task(id: 'k'));
    expect(box.get('k'), isNotNull);

    // Close cleanly so tearDownAll's Hive.deleteFromDisk does not hang.
    await box.close();
    // Clean up the blocker directory so tearDownAll can delete the temp dir.
    await blocker.delete(recursive: true);
  });
}
