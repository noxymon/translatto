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
  final double cropY;

  OverlayPainter({
    required this.translations,
    required this.imageSize,
    required this.cropY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize.width == 0 || imageSize.height == 0) return;

    final backgroundPaint = Paint()
      ..color = Colors.black.withAlpha(217)
      ..style = PaintingStyle.fill;

    final double scaleX = size.width / imageSize.width;
    final double scaleY = size.height / (imageSize.height + cropY);

    for (final block in translations) {
      final scaledRect = Rect.fromLTRB(
        block.rect.left * scaleX,
        (block.rect.top + cropY) * scaleY,
        block.rect.right * scaleX,
        (block.rect.bottom + cropY) * scaleY,
      );

      final double maxAllowedWidth = (size.width - 32.0).clamp(0.0, double.infinity);
      final double minLimit = maxAllowedWidth < 120.0 ? maxAllowedWidth : 120.0;
      final double textMaxWidth = (scaledRect.width * 1.6).clamp(minLimit, maxAllowedWidth);

      // Draw translated English text inside coordinates
      final textPainter = TextPainter(
        text: TextSpan(
          text: block.text,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout(maxWidth: textMaxWidth);

      final double actualTextWidth = textPainter.width;
      final double backgroundWidth = actualTextWidth + 8;
      
      final double centerX = scaledRect.left + scaledRect.width / 2;
      double boxLeft = centerX - backgroundWidth / 2;
      
      // Keep inside screen boundaries with 8dp margin
      if (boxLeft < 8) {
        boxLeft = 8;
      }
      if (boxLeft + backgroundWidth > size.width - 8) {
        boxLeft = size.width - 8 - backgroundWidth;
        if (boxLeft < 8) boxLeft = 8;
      }

      // Adjust the background rectangle's height dynamically based on the larger of scaledRect.height or textPainter.height (with padding)
      final dynamicHeight = textPainter.height > scaledRect.height 
          ? textPainter.height + 8 
          : scaledRect.height;

      final backgroundRect = Rect.fromLTRB(
        boxLeft,
        scaledRect.top,
        boxLeft + backgroundWidth,
        scaledRect.top + dynamicHeight,
      );

      // Paint solid background over original Japanese text bounds
      canvas.drawRect(backgroundRect, backgroundPaint);

      textPainter.paint(
        canvas,
        Offset(
          boxLeft + 4,
          scaledRect.top + (dynamicHeight - textPainter.height) / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant OverlayPainter oldDelegate) {
    return !listEquals(oldDelegate.translations, translations) ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.cropY != cropY;
  }
}
