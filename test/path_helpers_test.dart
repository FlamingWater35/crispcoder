import 'dart:io';

import 'package:crispcoder/core/utils/path_helpers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Fake platform that returns a fixed temp dir for getTemporaryDirectory().
class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.tempDir);

  final Directory tempDir;

  @override
  Future<String?> getTemporaryPath() async => tempDir.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('crispcoder_path_test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir);
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('clearAppCache removes everything by default', () async {
    // Create files + nested dirs
    final file1 = File(p.join(tempDir.path, 'a.mp4'));
    final file2 = File(p.join(tempDir.path, 'file_picker', 'b.mp4'));
    await file1.create(recursive: true);
    await file2.create(recursive: true);

    await PathHelpers.clearAppCache();

    expect(file1.existsSync(), isFalse);
    expect(file2.existsSync(), isFalse);
  });

  test('clearAppCache keeps protected files (incl. nested dir)', () async {
    final protected = File(
      p.join(tempDir.path, 'file_picker', 'completed.mp4'),
    );
    final other = File(p.join(tempDir.path, 'junk.mp4'));
    await protected.create(recursive: true);
    await other.create(recursive: true);

    await PathHelpers.clearAppCache(protect: {protected.path});

    // Protected file survives, its parent dir is not deleted
    expect(protected.existsSync(), isTrue);
    // Unprotected file is gone
    expect(other.existsSync(), isFalse);
  });

  test('clearAppCache keeps a protected file at the cache root', () async {
    final protected = File(p.join(tempDir.path, 'root_out.mp4'));
    await protected.create(recursive: true);

    await PathHelpers.clearAppCache(protect: {protected.path});

    expect(protected.existsSync(), isTrue);
  });

  test('deleteProcessedFilesFromAppData removes files but keeps dirs', () async {
    final outFile = File(p.join(tempDir.path, 'video_encoded.mp4'));
    final passesDir = Directory(p.join(tempDir.path, 'passes'));
    final passLog = File(p.join(passesDir.path, 'log.txt'));
    await outFile.create(recursive: true);
    await passLog.create(recursive: true);

    await PathHelpers.deleteProcessedFilesFromAppData();

    expect(outFile.existsSync(), isFalse);
    // The passes dir (FFmpeg logs) is not a "processed file" — it survives.
    expect(passLog.existsSync(), isTrue);
  });

  test('deleteProcessedFilesFromAppData removes the file_picker cache folder',
      () async {
    final picked = File(
      p.join(tempDir.path, 'file_picker', '29'),
    );
    await picked.create(recursive: true);

    await PathHelpers.deleteProcessedFilesFromAppData();

    expect(picked.existsSync(), isFalse);
  });

  test('deleteProcessedFilesFromAppData keeps protected entries', () async {
    final protected = File(p.join(tempDir.path, 'file_picker', 'keep.mp4'));
    final other = File(p.join(tempDir.path, 'remove.mp4'));
    await protected.create(recursive: true);
    await other.create(recursive: true);

    await PathHelpers.deleteProcessedFilesFromAppData(
      protect: {protected.path},
    );

    expect(protected.existsSync(), isTrue);
    expect(other.existsSync(), isFalse);
  });
}
