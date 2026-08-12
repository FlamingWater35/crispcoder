import 'dart:typed_data';

import 'package:hive_ce/hive_ce.dart';

/// Opens a Hive box that can never leave the caller with an unusable handle.
///
/// Hive's [Hive.openBox] throws when the on-disk box cannot be opened (e.g. a
/// corrupt or truncated `.hive` file that crash recovery cannot repair, or an
/// I/O failure). Callers that store the result in a `late` field then blow up
/// with `LateInitializationError` on first read, taking the whole provider
/// down. This helper removes that failure mode:
///
/// 1. Try the real on-disk box first (crash recovery enabled).
/// 2. If that throws, fall back to an in-memory box with the same name, so
///    reads return empty data and writes work for the lifetime of the process
///    instead of crashing the app.
///
/// The returned box is always usable. Persistence is best-effort: when the
/// fallback is used, data is not saved to disk (which is strictly better than
/// the app failing to start).
Future<Box<T>> openHiveBox<T>(String name) async {
  try {
    return await Hive.openBox<T>(name);
  } catch (_) {
    // In-memory fallback via the public API: `bytes:` selects
    // StorageBackendMemory (no disk path), so openBox cannot hit the disk.
    return Hive.openBox<T>(name, bytes: Uint8List(0));
  }
}
