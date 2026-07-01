import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

enum HandlePosition { topLeft, topRight, bottomLeft, bottomRight }

/// Interactive crop box overlay over a video player.
/// Renders a darkened mask outside the bounds, a 3x3 grid for composition,
/// and four draggable handles to resize the crop area.
class CropOverlay extends StatelessWidget {
  const CropOverlay({
    super.key,
    required this.controller,
    required this.cropRect,
    required this.aspectConstraint,
    required this.onCropChanged,
  });

  final VideoPlayerController controller;
  final Rect cropRect;
  final double? aspectConstraint; // Null for free
  final ValueChanged<Rect> onCropChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;

        return Stack(
          children: [
            VideoPlayer(controller),
            _buildDarkMask(width, height),
            _buildGridAndHandles(width, height),
          ],
        );
      },
    );
  }

  /// Builds four dark containers around the crop bounds to darken the excluded video area.
  Widget _buildDarkMask(double width, double height) {
    final left = cropRect.left * width;
    final top = cropRect.top * height;
    final w = cropRect.width * width;
    final h = cropRect.height * height;

    return IgnorePointer(
      child: Stack(
        children: [
          // Top mask
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            height: top,
            child: Container(color: Colors.black54),
          ),
          // Bottom mask
          Positioned(
            left: 0,
            top: top + h,
            right: 0,
            bottom: 0,
            child: Container(color: Colors.black54),
          ),
          // Left mask
          Positioned(
            left: 0,
            top: top,
            width: left,
            height: h,
            child: Container(color: Colors.black54),
          ),
          // Right mask
          Positioned(
            left: left + w,
            top: top,
            right: 0,
            height: h,
            child: Container(color: Colors.black54),
          ),
          // Border
          Positioned.fromRect(
            rect: Rect.fromLTWH(left, top, w, h),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Draws a 3x3 grid inside the crop box for composition and attaches handles.
  Widget _buildGridAndHandles(double width, double height) {
    final left = cropRect.left * width;
    final top = cropRect.top * height;
    final w = cropRect.width * width;
    final h = cropRect.height * height;

    return Positioned.fromRect(
      rect: Rect.fromLTWH(left, top, w, h),
      child: Stack(
        children: [
          // Grid Lines
          IgnorePointer(
            child: CustomPaint(size: Size.infinite, painter: _GridPainter()),
          ),
          // Move Body
          // Expanded SizedBox ensures hit testing covers the entire crop area
          MouseRegion(
            cursor: SystemMouseCursors.move,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (details) {
                final dx = details.delta.dx / width;
                final dy = details.delta.dy / height;
                double newLeft = (cropRect.left + dx).clamp(
                  0.0,
                  1.0 - cropRect.width,
                );
                double newTop = (cropRect.top + dy).clamp(
                  0.0,
                  1.0 - cropRect.height,
                );
                onCropChanged(
                  Rect.fromLTWH(
                    newLeft,
                    newTop,
                    cropRect.width,
                    cropRect.height,
                  ),
                );
              },
              child: const SizedBox.expand(),
            ),
          ),
          // Handles
          _buildHandle(HandlePosition.topLeft, width, height),
          _buildHandle(HandlePosition.topRight, width, height),
          _buildHandle(HandlePosition.bottomLeft, width, height),
          _buildHandle(HandlePosition.bottomRight, width, height),
        ],
      ),
    );
  }

  /// Individual draggable corner handle.
  /// Uses Transform.translate to avoid Container's negative margin assertion error.
  Widget _buildHandle(HandlePosition pos, double width, double height) {
    Alignment alignment = Alignment.center;
    double offsetX = 0, offsetY = 0;

    switch (pos) {
      case HandlePosition.topLeft:
        alignment = Alignment.topLeft;
        offsetX = -10;
        offsetY = -10;
        break;
      case HandlePosition.topRight:
        alignment = Alignment.topRight;
        offsetX = 10;
        offsetY = -10;
        break;
      case HandlePosition.bottomLeft:
        alignment = Alignment.bottomLeft;
        offsetX = -10;
        offsetY = 10;
        break;
      case HandlePosition.bottomRight:
        alignment = Alignment.bottomRight;
        offsetX = 10;
        offsetY = 10;
        break;
    }

    return Align(
      alignment: alignment,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeUpLeftDownRight,
        child: GestureDetector(
          onPanUpdate: (details) {
            double dx = details.delta.dx / width;
            double dy = details.delta.dy / height;

            double newLeft = cropRect.left;
            double newTop = cropRect.top;
            double newWidth = cropRect.width;
            double newHeight = cropRect.height;

            if (pos == HandlePosition.topLeft ||
                pos == HandlePosition.bottomLeft) {
              newLeft = (cropRect.left + dx).clamp(
                0.0,
                cropRect.left + cropRect.width - 0.05,
              );
              newWidth = cropRect.width - (newLeft - cropRect.left);
            } else {
              newWidth = (cropRect.width + dx).clamp(0.05, 1.0 - cropRect.left);
            }

            if (pos == HandlePosition.topLeft ||
                pos == HandlePosition.topRight) {
              newTop = (cropRect.top + dy).clamp(
                0.0,
                cropRect.top + cropRect.height - 0.05,
              );
              newHeight = cropRect.height - (newTop - cropRect.top);
            } else {
              newHeight = (cropRect.height + dy).clamp(
                0.05,
                1.0 - cropRect.top,
              );
            }

            // Enforce aspect ratio if constrained
            if (aspectConstraint != null) {
              if (pos == HandlePosition.topLeft ||
                  pos == HandlePosition.bottomLeft) {
                newWidth = newHeight * aspectConstraint!;
                if (newLeft + newWidth > 1.0) {
                  newWidth = 1.0 - newLeft;
                  newHeight = newWidth / aspectConstraint!;
                }
              } else {
                newHeight = newWidth / aspectConstraint!;
                if (newTop + newHeight > 1.0) {
                  newHeight = 1.0 - newTop;
                  newWidth = newHeight * aspectConstraint!;
                }
              }
            }

            onCropChanged(Rect.fromLTWH(newLeft, newTop, newWidth, newHeight));
          },
          child: Transform.translate(
            offset: Offset(offsetX, offsetY),
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.blue, width: 2),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Painter for drawing 3x3 composition grid lines.
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..strokeWidth = 1;

    // Vertical lines
    canvas.drawLine(
      Offset(size.width / 3, 0),
      Offset(size.width / 3, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 2 / 3, 0),
      Offset(size.width * 2 / 3, size.height),
      paint,
    );

    // Horizontal lines
    canvas.drawLine(
      Offset(0, size.height / 3),
      Offset(size.width, size.height / 3),
      paint,
    );
    canvas.drawLine(
      Offset(0, size.height * 2 / 3),
      Offset(size.width, size.height * 2 / 3),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
