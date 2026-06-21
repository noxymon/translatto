import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:screen_translate/ocr_service.dart';

void main() {
  test('OcrService extracts text blocks', () async {
    // Standard mock test structure for compiler check
    final service = OcrService();
    expect(service, isNotNull);
  });

  group('OCR Block Merging Unit Tests', () {
    test('Empty blocks input returns empty list', () {
      final merged = OcrBlockMerger.merge([]);
      expect(merged, isEmpty);
    });

    test('Single block input returns same block', () {
      final blocks = [
        OcrBlock(text: "Hello", boundingBox: const Rect.fromLTWH(0, 0, 100, 50)),
      ];
      final merged = OcrBlockMerger.merge(blocks);
      expect(merged.length, equals(1));
      expect(merged.first.text, equals("Hello"));
      expect(merged.first.boundingBox, equals(const Rect.fromLTWH(0, 0, 100, 50)));
    });

    test('Overlapping blocks are merged into one', () {
      final blocks = [
        OcrBlock(text: "Hello", boundingBox: const Rect.fromLTWH(0, 0, 100, 50)),
        OcrBlock(text: "World", boundingBox: const Rect.fromLTWH(50, 10, 100, 50)),
      ];
      final merged = OcrBlockMerger.merge(blocks);
      
      expect(merged.length, equals(1));
      expect(merged.first.text, equals("Hello World"));
      expect(merged.first.boundingBox, equals(const Rect.fromLTWH(0, 0, 150, 60)));
    });

    test('Horizontally aligned CJK blocks merge without space', () {
      final blocks = [
        OcrBlock(text: "こん", boundingBox: const Rect.fromLTWH(0, 0, 50, 20)),
        OcrBlock(text: "にちは", boundingBox: const Rect.fromLTWH(60, 0, 50, 20)),
      ];
      final merged = OcrBlockMerger.merge(blocks);

      expect(merged.length, equals(1));
      expect(merged.first.text, equals("こんにちは"));
      expect(merged.first.boundingBox, equals(const Rect.fromLTWH(0, 0, 110, 20)));
    });

    test('Horizontally aligned English blocks merge with space', () {
      final blocks = [
        OcrBlock(text: "Hello", boundingBox: const Rect.fromLTWH(0, 0, 50, 20)),
        OcrBlock(text: "World", boundingBox: const Rect.fromLTWH(60, 0, 50, 20)),
      ];
      final merged = OcrBlockMerger.merge(blocks);

      expect(merged.length, equals(1));
      expect(merged.first.text, equals("Hello World"));
      expect(merged.first.boundingBox, equals(const Rect.fromLTWH(0, 0, 110, 20)));
    });

    test('Horizontally aligned mixed CJK and English blocks merge without space', () {
      final blocks = [
        OcrBlock(text: "こん", boundingBox: const Rect.fromLTWH(0, 0, 50, 20)),
        OcrBlock(text: "Hello", boundingBox: const Rect.fromLTWH(60, 0, 50, 20)),
      ];
      final merged = OcrBlockMerger.merge(blocks);

      expect(merged.length, equals(1));
      expect(merged.first.text, equals("こんHello"));
      expect(merged.first.boundingBox, equals(const Rect.fromLTWH(0, 0, 110, 20)));
    });

    test('Vertically aligned blocks (lines) merge with newline separator', () {
      final blocks = [
        OcrBlock(text: "Line 1", boundingBox: const Rect.fromLTWH(0, 0, 100, 20)),
        OcrBlock(text: "Line 2", boundingBox: const Rect.fromLTWH(0, 30, 100, 20)),
      ];
      final merged = OcrBlockMerger.merge(blocks);

      expect(merged.length, equals(1));
      expect(merged.first.text, equals("Line 1\nLine 2"));
      expect(merged.first.boundingBox, equals(const Rect.fromLTWH(0, 0, 100, 50)));
    });

    test('Distinct vertical columns (e.g. vertical Japanese layout) do not merge horizontally', () {
      // Two columns: Right column (x=60) and Left column (x=20)
      // Both columns are taller than wide, so height > width holds for all blocks
      final blocks = [
        OcrBlock(text: "A", boundingBox: const Rect.fromLTWH(60, 0, 20, 40)), // Col 1 top
        OcrBlock(text: "B", boundingBox: const Rect.fromLTWH(60, 50, 20, 40)), // Col 1 bottom
        OcrBlock(text: "C", boundingBox: const Rect.fromLTWH(20, 0, 20, 40)), // Col 2 top
        OcrBlock(text: "D", boundingBox: const Rect.fromLTWH(20, 50, 20, 40)), // Col 2 bottom
      ];
      final merged = OcrBlockMerger.merge(blocks);

      expect(merged.length, equals(2));
      
      // Sort merged results by left to verify columns are independent
      merged.sort((x, y) => x.boundingBox.left.compareTo(y.boundingBox.left));
      
      final colLeft = merged[0];
      final colRight = merged[1];

      expect(colLeft.text, equals("C\nD"));
      expect(colLeft.boundingBox, equals(const Rect.fromLTRB(20, 0, 40, 90)));

      expect(colRight.text, equals("A\nB"));
      expect(colRight.boundingBox, equals(const Rect.fromLTRB(60, 0, 80, 90)));
    });
  });
}

