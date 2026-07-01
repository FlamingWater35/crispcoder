import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/encode_progress.dart';
import '../data/services/transcode_service.dart';

/// Tracks the live progress of the currently running encode (if any).
/// UI listens to this for percent / FPS / ETA updates.
final activeEncodeProvider =
    NotifierProvider<ActiveEncodeNotifier, EncodeProgress?>(
      ActiveEncodeNotifier.new,
    );

class ActiveEncodeNotifier extends Notifier<EncodeProgress?> {
  StreamSubscription<EncodeProgress>? _sub;

  @override
  EncodeProgress? build() {
    ref.onDispose(() => _sub?.cancel());
    return null;
  }

  /// Subscribes to a freshly started encode session's progress stream.
  void attach(ActiveSession session) {
    _sub?.cancel();
    _sub = session.progress.listen(
      (p) => state = p,
      onError: (_) => state = null,
      onDone: () => state = null,
    );
  }

  void detach() {
    _sub?.cancel();
    _sub = null;
    state = null;
  }
}
