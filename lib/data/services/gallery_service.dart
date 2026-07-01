import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';

/// Post-encode output handlers: save to MediaStore via `gal` or share.
class GalleryService {
  /// Returns true if the file was successfully inserted into the gallery.
  Future<bool> saveToGallery(String path, {String? album}) async {
    try {
      final hasAccess = await Gal.hasAccess(toAlbum: album != null);
      if (!hasAccess) {
        final granted = await Gal.requestAccess(toAlbum: album != null);
        if (!granted) {
          return false;
        }
      }
      await Gal.putVideo(path, album: album);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Shares the output file via the system share sheet.
  Future<void> share(String path, {String? subject}) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path)],
          subject: subject ?? 'VideoCode output',
        ),
      );
    } catch (_) {
      // Swallow — share sheet may be dismissed or unavailable
    }
  }
}

final galleryServiceProvider = Provider<GalleryService>(
  (ref) => GalleryService(),
);
