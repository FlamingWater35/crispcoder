/// Trim selection returned when the user saves in trim mode.
class TrimResult {
  final Duration start;
  final Duration end;

  const TrimResult(this.start, this.end);
}

/// Crop selection returned when the user saves in crop mode.
/// Values are fractions from 0.0 to 1.0 representing the video dimensions.
class CropResult {
  final double left;
  final double top;
  final double width;
  final double height;

  const CropResult(this.left, this.top, this.width, this.height);
}
