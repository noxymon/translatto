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

  static final Paint _backgroundPaint = Paint()
    ..color = Colors.black.withAlpha(217)
    ..style = PaintingStyle.fill;

  static final Map<_TextLayoutKey, TextPainter> _textPainterCache = {};

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize.width == 0 || imageSize.height == 0) return;

    final double scaleX = size.width / imageSize.width;
    final double scaleY = size.height / (imageSize.height + cropY);

    // First, compute original scaled bounds and limits for each block
    final List<_TempBlock> blocks = [];
    for (final block in translations) {
      final scaledRect = Rect.fromLTRB(
        block.rect.left * scaleX,
        (block.rect.top + cropY) * scaleY,
        block.rect.right * scaleX,
        (block.rect.bottom + cropY) * scaleY,
      );
      final double centerX = scaledRect.left + scaledRect.width / 2;
      
      blocks.add(_TempBlock(
        block: block,
        scaledRect: scaledRect,
        centerX: centerX,
        leftBound: 8.0,
        rightBound: size.width - 8.0,
      ));
    }

    // Adjust boundaries to resolve overlaps between any two blocks that overlap vertically
    for (int i = 0; i < blocks.length; i++) {
      for (int j = i + 1; j < blocks.length; j++) {
        final b1 = blocks[i];
        final b2 = blocks[j];

        // Check if there is vertical overlap
        final bool verticalOverlap = b1.scaledRect.top < b2.scaledRect.bottom &&
            b1.scaledRect.bottom > b2.scaledRect.top;

        if (verticalOverlap) {
          // Find mid point horizontally between centers
          final double mid = (b1.centerX + b2.centerX) / 2;
          if (b1.centerX < b2.centerX) {
            // b1 is on left, b2 on right
            if (b1.rightBound > mid - 2.0) {
              b1.rightBound = mid - 2.0;
            }
            if (b2.leftBound < mid + 2.0) {
              b2.leftBound = mid + 2.0;
            }
          } else {
            // b2 is on left, b1 on right
            if (b2.rightBound > mid - 2.0) {
              b2.rightBound = mid - 2.0;
            }
            if (b1.leftBound < mid + 2.0) {
              b1.leftBound = mid + 2.0;
            }
          }
        }
      }
    }

    // Now layout text and draw each block
    for (final b in blocks) {
      final double availableWidth = (b.rightBound - b.leftBound).clamp(0.0, double.infinity);
      // Tight paddings (2px horizontal inner padding on each side, so 4px total)
      final double maxAllowedWidth = (availableWidth - 4.0).clamp(0.0, double.infinity);
      
      final key = _TextLayoutKey(b.block.text, maxAllowedWidth);
      TextPainter? textPainter = _textPainterCache[key];
      if (textPainter == null) {
        if (_textPainterCache.length >= 100) {
          _textPainterCache.clear();
        }
        textPainter = TextPainter(
          text: TextSpan(
            text: b.block.text,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout(maxWidth: maxAllowedWidth);
        _textPainterCache[key] = textPainter;
      }

      final double actualTextWidth = textPainter.width;
      final double backgroundWidth = actualTextWidth + 4;

      // Position box centered around centerX if possible, but constrained to [leftBound, rightBound]
      double boxLeft = b.centerX - backgroundWidth / 2;
      if (boxLeft < b.leftBound) {
        boxLeft = b.leftBound;
      }
      if (boxLeft + backgroundWidth > b.rightBound) {
        boxLeft = b.rightBound - backgroundWidth;
        if (boxLeft < b.leftBound) boxLeft = b.leftBound;
      }

      final double dynamicHeight = textPainter.height + 2;
      // Position vertically centered matching original scaledRect
      final double boxTop = b.scaledRect.top + (b.scaledRect.height - dynamicHeight) / 2;

      final Rect bgRect = Rect.fromLTWH(boxLeft, boxTop, backgroundWidth, dynamicHeight);
      canvas.drawRect(bgRect, _backgroundPaint);

      textPainter.paint(
        canvas,
        Offset(
          boxLeft + 2,
          boxTop + 1,
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

class _TextLayoutKey {
  final String text;
  final double maxWidth;

  _TextLayoutKey(this.text, this.maxWidth);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _TextLayoutKey &&
        other.text == text &&
        (other.maxWidth - maxWidth).abs() < 0.01;
  }

  @override
  int get hashCode => text.hashCode ^ (maxWidth * 100).round().hashCode;
}

class _TempBlock {
  final TranslatedBlock block;
  final Rect scaledRect;
  final double centerX;
  double leftBound;
  double rightBound;

  _TempBlock({
    required this.block,
    required this.scaledRect,
    required this.centerX,
    required this.leftBound,
    required this.rightBound,
  });
}

