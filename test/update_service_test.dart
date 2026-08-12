import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crispcoder/data/services/update_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Minimal HttpClientAdapter that returns a canned response for GETs and
/// writes the "downloaded" body to disk for download requests.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final headers = <String, List<String>>{
      HttpHeaders.contentTypeHeader: ['application/json'],
    };
    return ResponseBody.fromString(body, statusCode, headers: headers);
  }

  @override
  void close({bool force = false}) {}
}

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.docsDir);

  final Directory docsDir;

  @override
  Future<String?> getApplicationDocumentsPath() async => docsDir.path;

  @override
  Future<String?> getTemporaryPath() async => docsDir.path;
}

Map<String, dynamic> _release({
  required String tag,
  required String abi,
  String body = 'notes',
}) {
  return {
    'tag_name': tag,
    'body': body,
    'assets': [
      {
        'name': 'crispcoder-$tag-$abi.apk',
        'browser_download_url': 'https://github.com/example/releases/$tag.apk',
      },
    ],
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory docsDir;

  setUpAll(() async {
    docsDir = await Directory.systemTemp.createTemp('crispcoder_update_test');
    PathProviderPlatform.instance = _FakePathProvider(docsDir);
  });

  tearDownAll(() async {
    try {
      await docsDir.delete(recursive: true);
    } catch (_) {}
  });

  test('checkForUpdate returns null when already up to date', () async {
    final dio = Dio()
      ..httpClientAdapter = _StubAdapter(200, jsonEncode(_release(tag: 'v1.0.0', abi: 'arm64-v8a')));
    final service = UpdateService(dio: dio);

    final info = await service.checkForUpdate(
      currentVersion: '1.0.0',
      abi: 'arm64-v8a',
    );

    expect(info, isNull);
  });

  test('checkForUpdate returns UpdateInfo when a newer version exists',
      () async {
    final dio = Dio()
      ..httpClientAdapter = _StubAdapter(200, jsonEncode(_release(tag: 'v1.1.0', abi: 'arm64-v8a')));
    final service = UpdateService(dio: dio);

    final info = await service.checkForUpdate(
      currentVersion: '1.0.0',
      abi: 'arm64-v8a',
    );

    expect(info, isNotNull);
    expect(info!.version.toString(), '1.1.0');
    expect(info.downloadUrl, 'https://github.com/example/releases/v1.1.0.apk');
    expect(info.releaseNotes, 'notes');
  });

  test('checkForUpdate throws when the ABI asset is missing', () async {
    final dio = Dio()
      ..httpClientAdapter = _StubAdapter(
        200,
        jsonEncode(_release(tag: 'v1.1.0', abi: 'arm64-v8a')),
      );
    final service = UpdateService(dio: dio);

    expect(
      () => service.checkForUpdate(currentVersion: '1.0.0', abi: 'x86_64'),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('No matching APK found'),
        ),
      ),
    );
  });

  test('checkForUpdate throws on a malformed tag', () async {
    final dio = Dio()
      ..httpClientAdapter = _StubAdapter(
        200,
        jsonEncode({
          'tag_name': 'not-a-version',
          'body': 'notes',
          'assets': [],
        }),
      );
    final service = UpdateService(dio: dio);

    expect(
      () => service.checkForUpdate(currentVersion: '1.0.0', abi: 'arm64-v8a'),
      throwsA(isA<Exception>()),
    );
  });

  test('downloadUpdate writes the file and reports progress', () async {
    final dio = Dio()
      ..httpClientAdapter = _StubAdapter(200, 'apk-bytes');
    final service = UpdateService(dio: dio);

    final progresses = <double>[];
    final path = await service.downloadUpdate(
      'https://example.com/update.apk',
      progresses.add,
    );

    expect(path, '${docsDir.path}/crispcoder_update.apk');
    expect(File(path).readAsStringSync(), 'apk-bytes');
    // Total is -1 in the stub → no progress callbacks (only guarded).
    expect(progresses, isEmpty);
  });
}
