import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class TranslatedBlock {
  final String text;
  final Rect rect;

  TranslatedBlock({required this.text, required this.rect});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TranslatedBlock &&
          runtimeType == other.runtimeType &&
          text == other.text &&
          rect == other.rect;

  @override
  int get hashCode => text.hashCode ^ rect.hashCode;
}

class OverlayPainter extends CustomPainter {
  final List<TranslatedBlock> translations;
  final Size imageSize;
  /// Physical pixel height of the status bar that was cropped from the
  /// screenshot. Added to each block's Y position so coordinates map
  /// from cropped-image space back into full-screen overlay space.
  final double cropYPixels;

  OverlayPainter({
    required this.translations,
    required this.imageSize,
    this.cropYPixels = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize.width == 0 || imageSize.height == 0) return;

    final backgroundPaint = Paint()
      ..color = Colors.black.withAlpha(217)
      ..style = PaintingStyle.fill;

    final double scaleX = size.width / imageSize.width;
    final double scaleY = size.height / imageSize.height;
    // Offset in canvas pixels to shift OCR coords (cropped-image space) into
    // full-screen overlay canvas space (which starts at the status bar top).
    final double yOffset = cropYPixels * scaleY;

    for (final block in translations) {
      final scaledRect = Rect.fromLTRB(
        block.rect.left * scaleX,
        block.rect.top * scaleY + yOffset,
        block.rect.right * scaleX,
        block.rect.bottom * scaleY + yOffset,
      );

      // Draw translated English text inside coordinates
      final double textMaxWidth = (scaledRect.width - 8).clamp(0.0, double.infinity);
      final textPainter = TextPainter(
        text: TextSpan(
          text: block.text,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout(maxWidth: textMaxWidth);

      // Adjust the background rectangle's height dynamically based on the larger of scaledRect.height or textPainter.height (with padding)
      final dynamicHeight = textPainter.height > scaledRect.height 
          ? textPainter.height + 8 
          : scaledRect.height;

      final backgroundRect = Rect.fromLTRB(
        scaledRect.left,
        scaledRect.top,
        scaledRect.right,
        scaledRect.top + dynamicHeight,
      );

      // Paint solid background over original Japanese text bounds
      canvas.drawRect(backgroundRect, backgroundPaint);

      textPainter.paint(
        canvas,
        Offset(
          scaledRect.left + 4,
          scaledRect.top + (dynamicHeight - textPainter.height) / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant OverlayPainter oldDelegate) {
    return !listEquals(oldDelegate.translations, translations) ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.cropYPixels != cropYPixels;
  }
}
