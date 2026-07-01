import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pub_semver/pub_semver.dart';

import '../../core/constants/app_constants.dart';

/// Represents the metadata for a fetched GitHub release.
class UpdateInfo {
  final Version version;
  final String downloadUrl;
  final String releaseNotes;

  UpdateInfo(this.version, this.downloadUrl, this.releaseNotes);
}

/// Handles checking GitHub releases for new versions, downloading APKs, and cleanup.
/// Throws descriptive exceptions so the UI can surface user-friendly errors.
class UpdateService {
  final Dio _dio = Dio();

  /// Fetches the latest release from GitHub and checks against the current version.
  /// Returns UpdateInfo if an update is available, otherwise null.
  Future<UpdateInfo?> checkForUpdate({
    required String currentVersion,
    required String abi,
  }) async {
    try {
      final uri = Uri.https(
        'api.github.com',
        '/repos/${AppConstants.githubOwner}/${AppConstants.githubRepo}/releases/latest',
      );
      final res = await _dio.getUri(
        uri,
        options: Options(headers: {'Accept': 'application/vnd.github+json'}),
      );

      if (res.statusCode != 200) {
        throw Exception('Failed to fetch release info');
      }

      final data = res.data is String ? jsonDecode(res.data) : res.data;
      final tagName = data['tag_name'] as String;

      // Clean version string (e.g., 'v1.0.0' -> '1.0.0')
      final cleanTag = tagName.startsWith('v') ? tagName.substring(1) : tagName;
      final latestVersion = Version.parse(cleanTag);
      final currentParsed = Version.parse(currentVersion);

      if (latestVersion <= currentParsed) return null;

      final assets = data['assets'] as List;
      final expectedAssetName = 'crispcoder-$tagName-$abi.apk';

      final asset = assets.firstWhere(
        (a) => (a as Map<String, dynamic>)['name'] == expectedAssetName,
        orElse: () => throw Exception('No matching APK found for ABI $abi'),
      );

      final downloadUrl = asset['browser_download_url'] as String;
      final releaseNotes =
          data['body'] as String? ?? 'No release notes provided.';

      return UpdateInfo(latestVersion, downloadUrl, releaseNotes);
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    } catch (e) {
      throw Exception('Update check failed: $e');
    }
  }

  /// Downloads the update APK to the app documents directory, reporting progress.
  Future<String> downloadUpdate(
    String url,
    void Function(double progress) onProgress,
  ) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final savePath = '${dir.path}/${AppConstants.updateFileName}';

      await _dio.download(
        url,
        savePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            onProgress(received / total);
          }
        },
        options: Options(headers: {HttpHeaders.acceptEncodingHeader: '*'}),
      );

      return savePath;
    } catch (e) {
      throw Exception('Download failed: $e');
    }
  }

  /// Deletes the downloaded update APK if it exists. Called on app boot.
  Future<void> cleanupUpdateFile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/${AppConstants.updateFileName}');
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Best-effort cleanup
    }
  }
}
