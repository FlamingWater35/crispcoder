import 'dart:io';

import 'package:crispcoder/core/constants/app_constants.dart';
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
}
