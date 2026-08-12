import 'dart:io';

import 'package:crispcoder/data/models/encode_task.dart';
import 'package:crispcoder/data/models/media_info.dart';
import 'package:crispcoder/data/models/transcode_preset.dart';
import 'package:crispcoder/data/repositories/app_settings_repository.dart';
import 'package:crispcoder/data/repositories/history_repository.dart';
import 'package:crispcoder/data/repositories/preset_repository.dart';
import 'package:crispcoder/data/repositories/queue_repository.dart';
import 'package:crispcoder/data/services/media_probe_service.dart';
import 'package:crispcoder/data/services/permission_service.dart';
import 'package:crispcoder/features/editor/editor_screen.dart';
import 'package:crispcoder/features/editor/widgets/editor_action_bar.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// No-op permission service so the picker flow never touches the real
/// permission_handler platform channels in tests.
class _FakePermissionService extends PermissionService {
  @override
  Future<void> requireMediaRead() async {}
}

/// Returns canned [MediaInfo] for any path so the picker flow can complete
/// without FFprobe.
class _FakeProbeService extends MediaProbeService {
  _FakeProbeService(super.ref);

  @override
  Future<MediaInfo> probe(String path) async =>
      MediaInfo(path: path, duration: const Duration(seconds: 60));
}

/// Stand-in for the file_picker platform, used to verify the fallback path.
class _FakeFilePicker extends FilePickerPlatform
    with MockPlatformInterfaceMixin {
  _FakeFilePicker(this._result);

  final FilePickerResult? _result;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
    bool cancelUploadOnWindowBlur = true,
    AndroidSAFOptions? androidSafOptions,
  }) async {
    return _result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('crispcoder/media_store');

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('editor_test');
    Hive.init(tempDir.path);
    Hive.registerAdapter(TranscodePresetAdapter());
    Hive.registerAdapter(EncodeTaskAdapter());
    Hive.registerAdapter(EncodeStatusAdapter());
    await AppSettingsRepository.instance.bootstrap();
    await PresetRepository.instance.bootstrap();
    await QueueRepository.instance.bootstrap();
    await HistoryRepository.instance.bootstrap();
  });

  Future<void> pumpEditor(
    WidgetTester tester, {
    bool mockPickVideo = true,
  }) async {
    if (mockPickVideo) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'pickVideo') {
          return {'name': 'My Video.mp4', 'path': '/cache/My Video.mp4'};
        }
        return null;
      });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          permissionServiceProvider.overrideWith(
            (ref) => _FakePermissionService(),
          ),
          mediaProbeServiceProvider.overrideWith(
            (ref) => _FakeProbeService(ref),
          ),
        ],
        child: const MaterialApp(home: EditorScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('initial view shows welcome and hides the action bar',
      (tester) async {
    await pumpEditor(tester);

    // Welcome view visible
    expect(find.text('Start a new encode'), findsOneWidget);
    expect(find.text('Select source video'), findsOneWidget);

    // No Preview / Start Encode buttons before a source is picked
    expect(find.byType(EditorActionBar), findsNothing);
    expect(find.text('Preview'), findsNothing);
    expect(find.text('Start Encode'), findsNothing);
  });

  testWidgets('native picker supplies the original name for the output field',
      (tester) async {
    await pumpEditor(tester);

    // Tap the source picker card → the native SAF picker (mocked) returns
    // the display name "My Video.mp4".
    await tester.tap(find.text('Select source video'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The editor loaded; the output name field is pre-filled with the
    // derived display name (extension stripped — the real one is added
    // automatically).
    final field = find.byKey(const ValueKey('output-name-field'));
    expect(field, findsOneWidget);
    final controller = tester
        .widget<TextFormField>(field)
        .controller;
    expect(controller?.text, 'My Video');
    expect(find.byType(EditorActionBar), findsOneWidget);
  });

  testWidgets('cancelling the native picker keeps the welcome view',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    await pumpEditor(tester, mockPickVideo: false);

    await tester.tap(find.text('Select source video'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // No pick → still the welcome view, no editor.
    expect(find.text('Start a new encode'), findsOneWidget);
    expect(find.byKey(const ValueKey('output-name-field')), findsNothing);
  });

  testWidgets('falls back to file_picker when the native method is missing',
      (tester) async {
    // Simulate the native method being absent: the mock handler throws
    // MissingPluginException (in the widget-test FakeAsync zone an
    // unregistered channel would hang instead, so it must be explicit).
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => throw MissingPluginException(
            'No implementation found for method pickVideo on channel '
            'crispcoder/media_store',
          ),
        );

    final originalPicker = FilePickerPlatform.instance;
    FilePickerPlatform.instance = _FakeFilePicker(
      FilePickerResult([
        PlatformFile(
          name: 'Fallback.mp4',
          size: 0,
          path: '/fallback/Fallback.mp4',
        ),
      ]),
    );
    addTearDown(() {
      FilePickerPlatform.instance = originalPicker;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await pumpEditor(tester, mockPickVideo: false);

    await tester.tap(find.text('Select source video'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final field = find.byKey(const ValueKey('output-name-field'));
    expect(field, findsOneWidget);
    final controller = tester
        .widget<TextFormField>(field)
        .controller;
    expect(controller?.text, 'Fallback');
  });

  testWidgets('native picker failure falls back to file_picker',
      (tester) async {
    // The native picker throws (e.g. COPY_FAILED) → the editor must fall
    // back to file_picker instead of stranding the user on an error.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => throw PlatformException(
            code: 'COPY_FAILED',
            message: 'Could not access the selected file',
          ),
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final originalPicker = FilePickerPlatform.instance;
    FilePickerPlatform.instance = _FakeFilePicker(
      FilePickerResult([
        PlatformFile(
          name: 'Recovered.mp4',
          size: 0,
          path: '/fallback/Recovered.mp4',
        ),
      ]),
    );
    addTearDown(() => FilePickerPlatform.instance = originalPicker);

    await pumpEditor(tester, mockPickVideo: false);

    await tester.tap(find.text('Select source video'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // No error view — the fallback picker succeeded and loaded the editor.
    expect(find.byKey(const ValueKey('output-name-field')), findsOneWidget);
    final controller = tester
        .widget<TextFormField>(find.byKey(const ValueKey('output-name-field')))
        .controller;
    expect(controller?.text, 'Recovered');
  });

  testWidgets('file_picker toggle routes to the package picker',
      (tester) async {
    var nativeCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'pickVideo') nativeCalls++;
      return null;
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    // Hive writes are real async I/O — must run inside runAsync to escape
    // the FakeAsync zone (same pattern as seed() in home_screen_test).
    // Reset first, then enable, so the toggle is deterministic regardless of
    // prior tests; the reset is deliberately NOT in addTearDown (teardown
    // runs in the FakeAsync zone where Hive writes hang).
    await tester.runAsync(() async {
      await AppSettingsRepository.instance.setUseFilePickerPackage(false);
      await AppSettingsRepository.instance.setUseFilePickerPackage(true);
    });

    final originalPicker = FilePickerPlatform.instance;
    FilePickerPlatform.instance = _FakeFilePicker(
      FilePickerResult([
        PlatformFile(
          name: 'Legacy.mp4',
          size: 0,
          path: '/fallback/Legacy.mp4',
        ),
      ]),
    );
    addTearDown(() => FilePickerPlatform.instance = originalPicker);

    await pumpEditor(tester, mockPickVideo: false);

    await tester.tap(find.text('Select source video'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      nativeCalls,
      0,
      reason: 'native channel must not be used when toggled on',
    );
    final controller = tester
        .widget<TextFormField>(find.byKey(const ValueKey('output-name-field')))
        .controller;
    expect(controller?.text, 'Legacy');
  });
}
