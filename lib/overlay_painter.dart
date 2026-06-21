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

    final List<_PlacedBlock> placedBlocks = [];

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

      final textPainter = TextPainter(
        text: TextSpan(
          text: block.text,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout(maxWidth: textMaxWidth);

      final double actualTextWidth = textPainter.width;
      final double backgroundWidth = actualTextWidth + 4;
      
      final double centerX = scaledRect.left + scaledRect.width / 2;
      double boxLeft = centerX - backgroundWidth / 2;
      
      if (boxLeft < 8) {
        boxLeft = 8;
      }
      if (boxLeft + backgroundWidth > size.width - 8) {
        boxLeft = size.width - 8 - backgroundWidth;
        if (boxLeft < 8) boxLeft = 8;
      }

      final dynamicHeight = textPainter.height + 2;

      placedBlocks.add(_PlacedBlock(
        block: block,
        boxLeft: boxLeft,
        boxWidth: backgroundWidth,
        textPainter: textPainter,
        dynamicHeight: dynamicHeight,
        top: scaledRect.top,
      ));
    }

    // Sort by boxLeft ascending (leftmost first)
    placedBlocks.sort((a, b) => a.boxLeft.compareTo(b.boxLeft));

    // Resolve overlaps by shifting rightward blocks downwards
    for (int i = 0; i < placedBlocks.length; i++) {
      bool hasOverlap = true;
      while (hasOverlap) {
        hasOverlap = false;
        final rectI = placedBlocks[i].rect;
        for (int j = 0; j < i; j++) {
          final rectJ = placedBlocks[j].rect;
          if (rectI.left < rectJ.right && rectI.right > rectJ.left &&
              rectI.top < rectJ.bottom && rectI.bottom > rectJ.top) {
            placedBlocks[i].top = rectJ.bottom + 4;
            hasOverlap = true;
            break; // Re-check from the beginning
          }
        }
      }
    }

    // Paint all blocks
    for (final pb in placedBlocks) {
      canvas.drawRect(pb.rect, backgroundPaint);

      pb.textPainter.paint(
        canvas,
        Offset(
          pb.boxLeft + 2,
          pb.top + (pb.dynamicHeight - pb.textPainter.height) / 2,
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

class _PlacedBlock {
  final TranslatedBlock block;
  final double boxLeft;
  final double boxWidth;
  final TextPainter textPainter;
  final double dynamicHeight;
  double top;

  _PlacedBlock({
    required this.block,
    required this.boxLeft,
    required this.boxWidth,
    required this.textPainter,
    required this.dynamicHeight,
    required this.top,
  });

  Rect get rect => Rect.fromLTWH(boxLeft, top, boxWidth, dynamicHeight);
}
