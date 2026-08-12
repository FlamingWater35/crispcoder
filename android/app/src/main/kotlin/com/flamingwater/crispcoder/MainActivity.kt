package com.flamingwater.crispcoder

import android.content.ContentValues
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.OutputStream

class MainActivity : FlutterActivity() {
    private val channelName = "crispcoder/media_store"

    companion object {
        private const val TAG = "CrispCoder"
    }

    /** Request code for the native video source picker (SAF). Kept distinct
     * from file_picker's own codes (0x4F50 / 0x4F51) so the two flows never
     * collide in [onActivityResult]. */
    private val pickVideoRequestCode = 0x4F52

    /** Pending MethodChannel result for the in-flight pickVideo call. */
    private var pendingPickVideoResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveToDCIM" -> {
                        val path = call.argument<String>("path")
                        val displayName = call.argument<String>("displayName")
                        val outputType = call.argument<String>("outputType") ?: "video"
                        if (path == null) {
                            result.error("INVALID_ARGUMENT", "path is required", null)
                            return@setMethodCallHandler
                        }
                        result.success(saveToDCIM(path, displayName, outputType))
                    }
                    "pickVideo" -> {
                        if (pendingPickVideoResult != null) {
                            result.error("PICKER_ACTIVE", "Video picker is already open", null)
                            return@setMethodCallHandler
                        }
                        pendingPickVideoResult = result
                        openVideoPicker()
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Opens the SAF documents picker for a single video.
     *
     * Deliberately NOT the Photo Picker (ACTION_PICK_IMAGES): SAF providers
     * are required to answer OpenableColumns.DISPLAY_NAME on every supported
     * API level, which is what makes original-filename detection reliable.
     */
    private fun openVideoPicker() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "video/*"
        }
        try {
            startActivityForResult(intent, pickVideoRequestCode)
        } catch (e: android.content.ActivityNotFoundException) {
            Log.e(TAG, "pickVideo: no SAF picker activity on this device", e)
            pendingPickVideoResult?.error("NO_PICKER", "No system file picker available", null)
            pendingPickVideoResult = null
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == pickVideoRequestCode) {
            handlePickVideoResult(resultCode, data)
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun handlePickVideoResult(resultCode: Int, data: Intent?) {
        val result = pendingPickVideoResult
        pendingPickVideoResult = null
        if (result == null) return

        when (resultCode) {
            RESULT_CANCELED -> result.success(null)
            RESULT_OK -> {
                val uri = data?.data
                if (uri == null) {
                    result.error("NO_URI", "No file selected", null)
                    return
                }
                val name = queryDisplayName(uri)
                Log.i(TAG, "pickVideo: uri=$uri displayName=$name")
                val path = resolveOrCopyPath(uri, name)
                if (path == null) {
                    result.error("COPY_FAILED", "Could not access the selected file", null)
                    return
                }
                result.success(mapOf("name" to (name ?: File(path).name), "path" to path))
            }
            else -> result.error("PICK_CANCELLED", "Video picker dismissed", null)
        }
    }

    /**
     * Recovers the human-friendly file name from a content URI.
     *
     * Priority order:
     *  1. AssetFileDescriptor extras — the SAF / Photo Picker provider
     *     attaches the REAL display name here (OpenableColumns.DISPLAY_NAME)
     *     without needing any READ_MEDIA permission (per-URI grant). This is
     *     the reliable source for photo-picker URIs.
     *  2. DISPLAY_NAME cursor query on the URI itself.
     *  3. MediaStore collections by numeric id (works for plain
     *     `content://media/...` URIs, where the id IS the MediaStore _ID).
     *  4. The URI path segment as a last resort.
     */
    private fun queryDisplayName(uri: Uri): String? {
        // 1) AssetFileDescriptor extras — provider-attached real name.
        try {
            contentResolver.openAssetFileDescriptor(uri, "r")?.use { afd ->
                val extras = afd.extras
                if (extras != null) {
                    val name = extras.getString(OpenableColumns.DISPLAY_NAME)
                    if (name != null && !isBareNumber(name)) return name
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "queryDisplayName: afd extras failed for $uri", e)
        }

        // 2) Direct DISPLAY_NAME query.
        var cursor: Cursor? = null
        val fromQuery = try {
            cursor = contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null,
            )
            if (cursor != null && cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) cursor.getString(index) else null
            } else {
                null
            }
        } catch (e: Exception) {
            Log.w(TAG, "queryDisplayName: DISPLAY_NAME failed for $uri", e)
            null
        } finally {
            cursor?.close()
        }

        if (fromQuery != null && !isBareNumber(fromQuery)) {
            return fromQuery
        }

        // 3) MediaStore by id (plain media URIs; photo-picker ids rarely match).
        val byId = queryMediaStoreName(uri)
        if (byId != null && !isBareNumber(byId)) {
            return byId
        }

        // 4) Last resort: the URI path segment.
        return fromQuery ?: uri.lastPathSegment
    }

    /** True when [value] is a bare number like "1000000037". */
    private fun isBareNumber(value: String): Boolean =
        value.trim().matches(Regex("\\d+"))

    /**
     * Queries the real MediaStore collections (video/audio/images) for the
     * DISPLAY_NAME of the media item identified by the numeric id at the end
     * of a photo-picker (or plain MediaStore) content URI.
     */
    private fun queryMediaStoreName(uri: Uri): String? {
        val id = uri.lastPathSegment?.trim() ?: return null
        if (!id.matches(Regex("\\d+"))) return null
        val collections = listOf(
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
        )
        for (collection in collections) {
            try {
                contentResolver.query(
                    collection,
                    arrayOf(OpenableColumns.DISPLAY_NAME),
                    "${MediaStore.MediaColumns._ID} = ?",
                    arrayOf(id),
                    null,
                ).use { c ->
                    if (c != null && c.moveToFirst()) {
                        val index = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (index >= 0) {
                            val name = c.getString(index)
                            if (name != null && !isBareNumber(name)) return name
                        }
                    }
                }
            } catch (_: Exception) {
                // Try the next collection
            }
        }
        return null
    }

    /**
     * Returns a filesystem path FFmpeg can read for the picked content URI.
     *
     * Tries the legacy DATA column for a direct /storage/... path first;
     * otherwise streams the bytes into the app cache using the display name so
     * the source is a real, named file (and survives the picker session).
     */
    private fun resolveOrCopyPath(uri: Uri, displayName: String?): String? {
        try {
            // Direct path when the provider exposes one (e.g. plain MediaStore
            // files picked on older providers) — avoids a full copy.
            val direct = queryDataPath(uri)
            if (direct != null && File(direct).exists() && File(direct).isFile) {
                return direct
            }
            return copyToCache(uri, displayName)
        } catch (e: Exception) {
            // Log the real cause instead of swallowing it: the Dart side only
            // sees COPY_FAILED, so Logcat is the only diagnostic trail.
            Log.w(TAG, "resolveOrCopyPath failed for $uri", e)
            return null
        }
    }

    private fun queryDataPath(uri: Uri): String? {
        return try {
            contentResolver.query(
                uri,
                arrayOf(MediaStore.MediaColumns.DATA),
                null,
                null,
                null,
            ).use { cursor ->
                if (cursor != null && cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(MediaStore.MediaColumns.DATA)
                    if (index >= 0) cursor.getString(index) else null
                } else {
                    null
                }
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun copyToCache(uri: Uri, displayName: String?): String? {
        return try {
            var safeName = (displayName ?: "picked_video").replace(Regex("[^A-Za-z0-9._-]"), "_")
            // Never copy under a bare numeric name — that's what made the
            // queue show video_<timestamp>. A real file named "123" (with a
            // real display name) is preserved; only the picker's numeric-id
            // fallback gets a meaningful base name.
            if (isBareNumber(safeName)) {
                safeName = "picked_video_${System.currentTimeMillis()}"
            }
            val cacheDir = File(cacheDir, "crispcoder_picked")
            if (!cacheDir.exists() && !cacheDir.mkdirs()) return null
            val dest = File(cacheDir, safeName)
            contentResolver.openInputStream(uri)?.use { input ->
                dest.outputStream().use { output -> input.copyTo(output) }
            } ?: return null
            if (dest.exists() && dest.length() > 0) dest.absolutePath else null
        } catch (e: Exception) {
            null
        }
    }

    /**
     * Publishes a finished output file into the device's media store.
     *
     * Video and subtitle outputs land in DCIM/Videolation; audio outputs go
     * to Music/CrispCoder — the Android **Audio** MediaStore collection
     * hard-rejects `DCIM` as a relative path (allowed dirs are Alarms,
     * Audiobooks, Music, Notifications, Podcasts, Recordings, Ringtones), so
     * publishing audio to DCIM throws IllegalArgumentException and the file
     * stays stranded in app-private storage.
     *
     * Works on all supported SDKs: Android 10+ uses scoped storage
     * (RELATIVE_PATH); Android 9 and below write directly with
     * WRITE_EXTERNAL_STORAGE (already declared, maxSdkVersion 29).
     *
     * Returns the MediaStore `content://` URI of the published copy on
     * success, or `null` on failure — logging the real exception so the Dart
     * side (and the user, via the Logs screen) can see why the publish failed
     * instead of silently losing the file to app-private storage.
     */
    private fun saveToDCIM(path: String, displayName: String?, outputType: String): String? {
        return try {
            val src = File(path)
            if (!src.exists() || !src.isFile) {
                Log.e(TAG, "saveToDCIM: source missing $path")
                return null
            }
            val name = displayName ?: src.name

            // Audio collection forbids DCIM; use an audio-legal directory.
            val relativePath = if (outputType == "audio") {
                "Music/CrispCoder"
            } else {
                "DCIM/Videolation"
            }
            // Legacy < Q writes to the same logical folders on disk.
            val legacyDir = if (outputType == "audio") {
                File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC), "CrispCoder")
            } else {
                File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DCIM), "Videolation")
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val collection = when (outputType) {
                    "audio" -> MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                    "subtitle" -> MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                    else -> MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                }
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                    put(MediaStore.MediaColumns.MIME_TYPE, mimeTypeFor(outputType, name))
                    put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
                val uri = contentResolver.insert(collection, values)
                    ?: run {
                        Log.e(TAG, "saveToDCIM: insert returned null for $name")
                        return null
                    }
                try {
                    val os: OutputStream = contentResolver.openOutputStream(uri)
                        ?: run {
                            Log.e(TAG, "saveToDCIM: no output stream for $uri")
                            contentResolver.delete(uri, null, null)
                            return null
                        }
                    FileInputStream(src).use { input ->
                        os.use { output -> input.copyTo(output) }
                    }
                    values.clear()
                    values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                    contentResolver.update(uri, values, null, null)
                    uri.toString()
                } catch (e: Exception) {
                    Log.e(TAG, "saveToDCIM: copy failed for $path", e)
                    contentResolver.delete(uri, null, null)
                    null
                }
            } else {
                // Legacy storage (API < 29): write directly to the folder
                // matching the output type (Music/CrispCoder for audio,
                // DCIM/Videolation otherwise).
                if (!legacyDir.exists() && !legacyDir.mkdirs()) {
                    Log.e(TAG, "saveToDCIM: cannot create $legacyDir")
                    return null
                }
                // Avoid silently overwriting an existing same-name file:
                // append " (n)" like PathHelpers.uniqueOutputPath does on the
                // Dart side, so two encodes with the same base name both
                // survive.
                val base = name.substringBeforeLast('.')
                val ext = name.substringAfterLast('.', "")
                var dest = File(legacyDir, name)
                var attempt = 1
                while (dest.exists()) {
                    val suffix = if (ext.isEmpty()) "($attempt)" else "($attempt).$ext"
                    dest = File(legacyDir, "$base $suffix")
                    attempt++
                }
                FileInputStream(src).use { input ->
                    dest.outputStream().use { output -> input.copyTo(output) }
                }
                // No content URI on legacy storage; return the file path.
                // This is NOT a content:// URI — it is persisted as
                // publishedUri but share_plus/file IO resolve real paths, so
                // sharing still works. Don't "fix" this to look like a URI.
                dest.absolutePath
            }
        } catch (e: Exception) {
            Log.e(TAG, "saveToDCIM failed for $path", e)
            null
        }
    }

    private fun mimeTypeFor(outputType: String, name: String): String {
        return when (outputType) {
            "audio" -> when {
                name.endsWith(".mp3", ignoreCase = true) -> "audio/mpeg"
                name.endsWith(".m4a", ignoreCase = true) -> "audio/mp4"
                name.endsWith(".opus", ignoreCase = true) ||
                    name.endsWith(".ogg", ignoreCase = true) -> "audio/ogg"
                name.endsWith(".flac", ignoreCase = true) -> "audio/flac"
                else -> "audio/*"
            }
            "subtitle" -> when {
                name.endsWith(".ass", ignoreCase = true) -> "text/x-ssa"
                else -> "application/x-subrip"
            }
            else -> "video/mp4"
        }
    }
}
