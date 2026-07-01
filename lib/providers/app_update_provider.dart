import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/services/device_capability_service.dart';
import '../data/services/update_service.dart';

/// Status enum for the update lifecycle.
enum UpdateStatus {
  idle,
  checking,
  noUpdate,
  updateAvailable,
  downloading,
  readyToInstall,
  error,
}

/// Immutable state holding update status, info, and progress.
class AppUpdateState {
  final UpdateStatus status;
  final UpdateInfo? updateInfo;
  final double downloadProgress;
  final String? errorMessage;
  final String? downloadedPath;

  const AppUpdateState({
    this.status = UpdateStatus.idle,
    this.updateInfo,
    this.downloadProgress = 0,
    this.errorMessage,
    this.downloadedPath,
  });

  AppUpdateState copyWith({
    UpdateStatus? status,
    UpdateInfo? updateInfo,
    double? downloadProgress,
    String? errorMessage,
    String? downloadedPath,
  }) {
    return AppUpdateState(
      status: status ?? this.status,
      updateInfo: updateInfo ?? this.updateInfo,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      errorMessage: errorMessage,
      downloadedPath: downloadedPath ?? this.downloadedPath,
    );
  }
}

/// Reactive update checker and downloader controller.
final appUpdateProvider = NotifierProvider<AppUpdateNotifier, AppUpdateState>(
  AppUpdateNotifier.new,
);

class AppUpdateNotifier extends Notifier<AppUpdateState> {
  final _service = UpdateService();

  @override
  AppUpdateState build() => const AppUpdateState();

  /// Queries GitHub for the latest release and compares versions.
  Future<void> checkForUpdate() async {
    state = state.copyWith(status: UpdateStatus.checking, errorMessage: null);
    try {
      final info = await PackageInfo.fromPlatform();
      final currentVersion = info.version;

      final cap = await ref.read(deviceCapabilityServiceProvider).detect();
      final abi = cap.abis.first;

      final updateInfo = await _service.checkForUpdate(
        currentVersion: currentVersion,
        abi: abi,
      );

      if (updateInfo != null) {
        state = state.copyWith(
          status: UpdateStatus.updateAvailable,
          updateInfo: updateInfo,
        );
      } else {
        state = state.copyWith(status: UpdateStatus.noUpdate);
      }
    } catch (e) {
      state = state.copyWith(
        status: UpdateStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  /// Starts downloading the APK for the available update.
  Future<void> downloadUpdate() async {
    final info = state.updateInfo;
    if (info == null) return;

    state = state.copyWith(
      status: UpdateStatus.downloading,
      downloadProgress: 0,
    );

    try {
      final path = await _service.downloadUpdate(info.downloadUrl, (progress) {
        state = state.copyWith(downloadProgress: progress);
      });
      state = state.copyWith(
        status: UpdateStatus.readyToInstall,
        downloadedPath: path,
      );
    } catch (e) {
      state = state.copyWith(
        status: UpdateStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  /// Resets state back to idle (e.g., user dismisses the UI).
  void reset() {
    state = const AppUpdateState();
  }
}
