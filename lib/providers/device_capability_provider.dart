import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/device_capability.dart';
import '../data/services/device_capability_service.dart';

/// Async-loaded device capability; resolved once at app startup.
final deviceCapabilityProvider = FutureProvider<DeviceCapability>((ref) async {
  final svc = ref.watch(deviceCapabilityServiceProvider);
  return svc.detect();
});
