/// Base type for all domain errors so callers can catch broadly if needed.
sealed class AppException implements Exception {
  final String userMessage;
  final String? technicalDetail;
  AppException(this.userMessage, [this.technicalDetail]);

  @override
  String toString() =>
      technicalDetail == null ? userMessage : '$userMessage ($technicalDetail)';
}

/// Raised when the FFmpeg session returns a non-success return code.
class TranscodeFailedException extends AppException {
  final int returnCode;
  TranscodeFailedException(this.returnCode, {String? log})
    : super('Transcode failed (code $returnCode).', log);
}

/// Raised when the source media could not be parsed or located.
class ProbeFailedException extends AppException {
  ProbeFailedException(String detail)
    : super('Could not read source media.', detail);
}

/// Raised when the chosen output path is not writable or out of disk space.
class OutputNotWritableException extends AppException {
  OutputNotWritableException(String detail)
    : super('Cannot write the output file.', detail);
}

/// Raised when the user cancels an encode.
class EncodeCancelledException extends AppException {
  EncodeCancelledException() : super('Encode was cancelled.');
}

/// Raised when a required runtime permission is missing.
class MissingPermissionException extends AppException {
  MissingPermissionException(String permission)
    : super('Required permission not granted: $permission.');
}
