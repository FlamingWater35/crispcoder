import 'package:crispcoder/data/services/permission_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';

/// Records which permissions were requested and always grants them.
class _RecordingPermissionHandler extends PermissionHandlerPlatform {
  final requested = <Permission>[];

  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async {
    return PermissionStatus.granted;
  }

  @override
  Future<ServiceStatus> checkServiceStatus(Permission permission) async {
    return ServiceStatus.notApplicable;
  }

  @override
  Future<Map<Permission, PermissionStatus>> requestPermissions(
    List<Permission> permissions,
  ) async {
    requested.addAll(permissions);
    return {
      for (final p in permissions) p: PermissionStatus.granted,
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingPermissionHandler handler;

  setUp(() {
    handler = _RecordingPermissionHandler();
    PermissionHandlerPlatform.instance = handler;
  });

  test('audio read is skipped on Android < 33 (no microphone prompt)', () async {
    final service = PermissionService()
      ..sdkIntProvider = () async => 32;

    final granted = await service.requireAudioRead();

    // No runtime permission request may be issued on API 32 and below:
    // READ_MEDIA_AUDIO does not exist there and the manifest declares no
    // RECORD_AUDIO, so requesting would always be denied (or prompt for the
    // microphone on some handlers).
    expect(granted, isTrue);
    expect(handler.requested, isEmpty);
  });

  test('audio read is requested on Android 33+', () async {
    final service = PermissionService()
      ..sdkIntProvider = () async => 33;

    final granted = await service.requireAudioRead();

    expect(granted, isTrue);
    expect(handler.requested, contains(Permission.audio));
  });

  test('audio read falls back to requesting when SDK is unknown', () async {
    final service = PermissionService()
      ..sdkIntProvider = () async => null;

    final granted = await service.requireAudioRead();

    expect(granted, isTrue);
    expect(handler.requested, contains(Permission.audio));
  });
}
