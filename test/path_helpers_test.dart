import 'dart:io';

import 'package:crispcoder/core/utils/path_helpers.dart';
import 'package:crispcoder/data/models/transcode_preset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Fake platform that returns fixed temp + documents dirs.
class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.tempDir, this.docsDir);

  final Directory tempDir;
  final Directory docsDir;

  @override
  Future<String?> getTemporaryPath() async => tempDir.path;

  @override
  Future<String?> getApplicationDocumentsPath() async => docsDir.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory docsDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('crispcoder_path_test');
    docsDir = await Directory.systemTemp.createTemp('crispcoder_docs_test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir, docsDir);
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
    try {
      await docsDir.delete(recursive: true);
    } catch (_) {}
  });

  group('clearAppCache', () {
    test('removes everything by default', () async {
      final file1 = File(p.join(tempDir.path, 'a.mp4'));
      final file2 = File(p.join(tempDir.path, 'file_picker', 'b.mp4'));
      await file1.create(recursive: true);
      await file2.create(recursive: true);

      await PathHelpers.clearAppCache();

      expect(file1.existsSync(), isFalse);
      expect(file2.existsSync(), isFalse);
    });

    test('keeps protected files (incl. nested dir)', () async {
      final protected = File(
        p.join(tempDir.path, 'file_picker', 'completed.mp4'),
      );
      final other = File(p.join(tempDir.path, 'junk.mp4'));
      await protected.create(recursive: true);
      await other.create(recursive: true);

      await PathHelpers.clearAppCache(protect: {protected.path});

      expect(protected.existsSync(), isTrue);
      expect(other.existsSync(), isFalse);
    });

    test('keeps a protected file at the cache root', () async {
      final protected = File(p.join(tempDir.path, 'root_out.mp4'));
      await protected.create(recursive: true);

      await PathHelpers.clearAppCache(protect: {protected.path});

      expect(protected.existsSync(), isTrue);
    });

    test('protecting a file does not protect a sibling with a shared prefix',
        () async {
      // Regression: /a/cache/file must not protect /a/cache/file2.
      final protected = File(p.join(tempDir.path, 'file'));
      final sibling = File(p.join(tempDir.path, 'file2'));
      await protected.create(recursive: true);
      await sibling.create(recursive: true);

      await PathHelpers.clearAppCache(protect: {protected.path});

      expect(protected.existsSync(), isTrue);
      expect(sibling.existsSync(), isFalse);
    });
  });

  group('deleteProcessedFilesFromAppData', () {
    test('removes files but keeps dirs', () async {
      final outFile = File(p.join(tempDir.path, 'video_encoded.mp4'));
      final passesDir = Directory(p.join(tempDir.path, 'passes'));
      final passLog = File(p.join(passesDir.path, 'log.txt'));
      await outFile.create(recursive: true);
      await passLog.create(recursive: true);

      await PathHelpers.deleteProcessedFilesFromAppData();

      expect(outFile.existsSync(), isFalse);
      expect(passLog.existsSync(), isTrue);
    });

    test('removes the file_picker cache folder', () async {
      final picked = File(p.join(tempDir.path, 'file_picker', '29'));
      await picked.create(recursive: true);

      await PathHelpers.deleteProcessedFilesFromAppData();

      expect(picked.existsSync(), isFalse);
    });

    test('removes the native picker crispcoder_picked cache folder', () async {
      // Picked-source copies under their display names land in
      // cache/crispcoder_picked — they are transient and must be purged.
      final picked = File(
        p.join(tempDir.path, 'crispcoder_picked', 'My Video.mp4'),
      );
      await picked.create(recursive: true);

      await PathHelpers.deleteProcessedFilesFromAppData();

      expect(picked.existsSync(), isFalse);
    });

    test('keeps protected entries', () async {
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
  });

  group('deriveDisplayName', () {
    test('uses the picker name when it looks real', () {
      final name = PathHelpers.deriveDisplayName(
        pickerName: 'My Video.mp4',
        path: '/cache/file_picker/29',
      );
      expect(name, 'My Video.mp4');
    });

    test('falls back to the path basename when picker name is null', () {
      final name = PathHelpers.deriveDisplayName(
        pickerName: null,
        path: '/media/videos/vacation.mp4',
      );
      expect(name, 'vacation.mp4');
    });

    test('numeric picker name falls back to a readable timestamped name', () {
      final name = PathHelpers.deriveDisplayName(
        pickerName: '29',
        path: '/data/user/0/app/cache/file_picker/29',
      );
      expect(name, startsWith('video_20')); // timestamped fallback
      expect(RegExp(r'^\d+$').hasMatch(name), isFalse);
    });

    test('timestamped fallback never invents a .mp4 extension', () {
      // The fake ".mp4" used to leak into audio/subtitle extraction titles.
      // The fallback must be a bare timestamped name; the real extension is
      // derived from the output type later.
      for (final pickerName in ['29', null]) {
        final name = PathHelpers.deriveDisplayName(
          pickerName: pickerName,
          path: '/cache/file_picker/29',
        );
        expect(name, startsWith('video_20'));
        expect(name.endsWith('.mp4'), isFalse,
            reason: 'fallback for "$pickerName" must not invent .mp4');
        expect(name.contains('.'), isFalse,
            reason: 'fallback for "$pickerName" must have no extension');
      }
    });

    test('bare-number path basename falls back too', () {
      final name = PathHelpers.deriveDisplayName(
        pickerName: null,
        path: '/cache/file_picker/29',
      );
      expect(name, startsWith('video_20'));
    });

    test('metadata title is used when picker name is numeric', () {
      final name = PathHelpers.deriveDisplayName(
        pickerName: '42',
        path: '/cache/file_picker/42',
        metadataTitle: 'Concert Highlights',
      );
      expect(name, 'Concert Highlights');
    });

    test('meaningful path basename wins over a bare-number picker name', () {
      // The Android photo picker can report a numeric id as the "name"; if
      // the underlying path still carries the real file name (e.g. the cache
      // copy was named after the display name), use that instead of
      // degrading to video_<timestamp>.
      final name = PathHelpers.deriveDisplayName(
        pickerName: '1000000037',
        path: '/cache/crispcoder_picked/My Video.mp4',
      );
      expect(name, 'My Video.mp4');
    });

    test('meaningful picker name still wins over the path basename', () {
      final name = PathHelpers.deriveDisplayName(
        pickerName: 'My Video.mp4',
        path: '/cache/crispcoder_picked/1000000037',
      );
      expect(name, 'My Video.mp4');
    });
  });

  group('safeOutputBaseName', () {
    test('keeps a real name without extension', () {
      expect(PathHelpers.safeOutputBaseName('My Video.mp4'), 'My Video');
    });

    test('sanitizes invalid filename characters', () {
      expect(PathHelpers.safeOutputBaseName('a:b*c.mp4'), 'a_b_c');
    });

    test('numeric name falls back to a timestamped name', () {
      final result = PathHelpers.safeOutputBaseName('29');
      expect(result, startsWith('video_'));
      expect(RegExp(r'^\d+$').hasMatch(result), isFalse);
    });

    test('empty name falls back to a timestamped name', () {
      final result = PathHelpers.safeOutputBaseName('');
      expect(result, startsWith('video_'));
      expect(result, isNotEmpty);
    });
  });

  group('resolveOutputDirectory', () {
    test('custom directory wins for video, audio, and subtitle', () async {
      for (final type in OutputType.values) {
        final dir = await PathHelpers.resolveOutputDirectory(
          outputType: type,
          customDirectory: '/sdcard/CrispCoder',
          sourcePath: '/cache/file_picker/29',
        );
        expect(dir, '/sdcard/CrispCoder');
      }
    });

    test('video defaults to the source directory', () async {
      final dir = await PathHelpers.resolveOutputDirectory(
        outputType: OutputType.video,
        customDirectory: null,
        sourcePath: '/media/videos/vacation.mp4',
      );
      expect(dir, '/media/videos');
    });

    test('audio defaults to app documents/CrispCoder/Audio', () async {
      final dir = await PathHelpers.resolveOutputDirectory(
        outputType: OutputType.audio,
        customDirectory: null,
        sourcePath: '/cache/file_picker/29',
      );
      expect(dir, p.join(docsDir.path, 'CrispCoder', 'Audio'));
    });

    test('subtitle defaults to app documents/CrispCoder/Subtitles', () async {
      final dir = await PathHelpers.resolveOutputDirectory(
        outputType: OutputType.subtitle,
        customDirectory: null,
        sourcePath: '/cache/file_picker/29',
      );
      expect(dir, p.join(docsDir.path, 'CrispCoder', 'Subtitles'));
    });

    test('whitespace-only custom directory is treated as unset', () async {
      final dir = await PathHelpers.resolveOutputDirectory(
        outputType: OutputType.audio,
        customDirectory: '   ',
        sourcePath: '/cache/file_picker/29',
      );
      expect(dir, p.join(docsDir.path, 'CrispCoder', 'Audio'));
    });
  });
}
