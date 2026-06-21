import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class TranslatedBlock {
  final String text;
  final Rect rect;

  TranslatedBlock({required this.text, required this.rect});
}

class OverlayPainter extends CustomPainter {
  final List<TranslatedBlock> translations;
  final Size imageSize;

  OverlayPainter({required this.translations, required this.imageSize});

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize.width == 0 || imageSize.height == 0) return;

    final backgroundPaint = Paint()
      ..color = Colors.black.withAlpha(217)
      ..style = PaintingStyle.fill;

    final double scaleX = size.width / imageSize.width;
    final double scaleY = size.height / imageSize.height;

    for (final block in translations) {
      final scaledRect = Rect.fromLTRB(
        block.rect.left * scaleX,
        block.rect.top * scaleY,
        block.rect.right * scaleX,
        block.rect.bottom * scaleY,
      );

      // Paint solid background over original Japanese text bounds
      canvas.drawRect(scaledRect, backgroundPaint);

      // Draw translated English text inside coordinates
      final textPainter = TextPainter(
        text: TextSpan(
          text: block.text,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout(maxWidth: scaledRect.width);
      textPainter.paint(
        canvas,
        Offset(
          scaledRect.left + 4,
          scaledRect.top + (scaledRect.height - textPainter.height) / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant OverlayPainter oldDelegate) {
    return !listEquals(oldDelegate.translations, translations) || oldDelegate.imageSize != imageSize;
  }
}
