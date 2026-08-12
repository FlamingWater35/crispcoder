import 'package:crispcoder/data/models/transcode_preset.dart';
import 'package:crispcoder/data/services/gallery_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('crispcoder/media_store');

  group('saveToDCIM', () {
    test('invokes the platform channel and returns the MediaStore URI',
        () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return 'content://media/external/audio/media/42';
      });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final uri = await GalleryService().saveToDCIM(
        path: '/tmp/out/MySong_encoded.m4a',
        outputType: OutputType.audio,
        displayName: 'MySong_encoded.m4a',
      );

      expect(uri, 'content://media/external/audio/media/42');
      expect(calls, hasLength(1));
      expect(calls.single.method, 'saveToDCIM');
      expect(calls.single.arguments['path'], '/tmp/out/MySong_encoded.m4a');
      expect(calls.single.arguments['displayName'], 'MySong_encoded.m4a');
      expect(calls.single.arguments['outputType'], 'audio');
    });

    test('returns null when the channel reports failure', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => null);
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final uri = await GalleryService().saveToDCIM(
        path: '/tmp/out/x.mp4',
        outputType: OutputType.video,
      );
      expect(uri, isNull);
    });

    test(
        'audio/subtitle output is not saved when the platform channel is '
        'unavailable', () async {
      // No handler registered → MissingPluginException on the channel.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);

      for (final type in [OutputType.audio, OutputType.subtitle]) {
        final uri = await GalleryService().saveToDCIM(
          path: '/tmp/out/x.m4a',
          outputType: type,
        );
        expect(uri, isNull, reason: '$type must not fall back to Gal');
      }
    });
  });

  group('pickVideo', () {
    test('returns the display name and path from the native picker', () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return {'name': 'My Video.mp4', 'path': '/cache/My Video.mp4'};
      });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final picked = await GalleryService().pickVideo();

      expect(picked, isNotNull);
      expect(picked!.name, 'My Video.mp4');
      expect(picked.path, '/cache/My Video.mp4');
      expect(calls.single.method, 'pickVideo');
    });

    test('returns null when the user cancels the picker', () async {
      // The native side calls result.success(null) on cancel. A mock handler
      // returning null is decoded by the codec as a null success envelope —
      // exactly what a cancelled picker produces.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => null);
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      expect(await GalleryService().pickVideo(), isNull);
    });

    test('throws MissingPluginException when the native method is absent',
        () async {
      // No handler → the channel is unregistered, same as a stale build or
      // a non-Android platform. The editor falls back to file_picker here.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);

      expect(
        () => GalleryService().pickVideo(),
        throwsA(isA<MissingPluginException>()),
      );
    });
  });
}
