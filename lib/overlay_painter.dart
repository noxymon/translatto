import 'package:flutter/material.dart';

class TranslatedBlock {
  final String text;
  final Rect rect;

  TranslatedBlock({required this.text, required this.rect});
}

class OverlayPainter extends CustomPainter {
  final List<TranslatedBlock> translations;

  OverlayPainter({required this.translations});

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPaint = Paint()
      ..color = Colors.black.withAlpha(217)
      ..style = PaintingStyle.fill;

    for (final block in translations) {
      // Paint solid background over original Japanese text bounds
      canvas.drawRect(block.rect, backgroundPaint);

      // Draw translated English text inside coordinates
      final textPainter = TextPainter(
        text: TextSpan(
          text: block.text,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout(maxWidth: block.rect.width);
      textPainter.paint(
        canvas,
        Offset(block.rect.left + 4, block.rect.top + (block.rect.height - textPainter.height) / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant OverlayPainter oldDelegate) {
    return oldDelegate.translations != translations;
  }
}
