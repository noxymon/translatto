# Analysis: OCR Block Merging in Dart

**Summary of Core Findings**:
OCR block merging can be implemented cleanly by introducing a custom `OcrBlock` class that wraps text and `boundingBox` (Flutter's `Rect`), allowing us to bypass the read-only limitations of native ML Kit `TextBlock` objects. Merging should be executed sequentially in three phases (Overlaps, Horizontal Alignment, and Vertical Alignment) with aspect-ratio heuristics to prevent separate vertical columns of text (e.g., vertical Japanese) from being merged horizontally.

---

## 1. Where `extractText` is Called and How Results are Returned

### Caller Analysis
*   **File**: `lib/main.dart` (lines 93–104)
*   **Context**: Inside `_runTranslationFlowAndSendToOverlay()`, the OCR service is called to process the screen screenshot:
    ```dart
    // lib/main.dart line 93
    final ocrBlocks = await _ocrService.extractText(path);
    ```
*   **Return Type**: Currently `Future<List<TextBlock>>` where `TextBlock` is imported from `package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart`.

### How Results are Utilized
The retrieved blocks are mapped to record structures for translation batch processing and later painter rendering:
```dart
// lib/main.dart lines 100-104
final blockRecords = ocrBlocks.map((b) => (
  text: b.text,
  x: b.boundingBox.left.toInt(),
  y: b.boundingBox.top.toInt(),
)).toList();
```
```dart
// lib/main.dart lines 109-118
for (int i = 0; i < ocrBlocks.length; i++) {
  final block = ocrBlocks[i];
  final rect = block.boundingBox;
  ...
```

### Proposed Signature Update
Because native ML Kit `TextBlock` objects do not have public constructors for manual instantiation (preventing us from creating new merged blocks of type `TextBlock`), we propose introducing a custom wrapper class `OcrBlock`:
```dart
class OcrBlock {
  final String text;
  final Rect boundingBox;

  OcrBlock({required this.text, required this.boundingBox});
}
```
If `OcrService.extractText` is refactored to return `Future<List<OcrBlock>>`, Dart's type inference (`final ocrBlocks = ...`) allows `lib/main.dart` to compile and run with **zero modifications**, as `OcrBlock` exposes the exact same properties (`text` and `boundingBox`) required by the callers.

---

## 2. Modeling Coordinates and Rectangles

*   **Coordinate Model**: Coordinates are modeled using Flutter's standard `Rect` class from the `dart:ui` package.
*   **Rect Properties Used**:
    *   `left`: Minimum horizontal coordinate (x).
    *   `top`: Minimum vertical coordinate (y).
    *   `right`: Maximum horizontal coordinate (x + width).
    *   `bottom`: Maximum vertical coordinate (y + height).
    *   `width`: Horizontal size (`right - left`).
    *   `height`: Vertical size (`bottom - top`).
*   **Standard Methods**: `Rect.overlaps(Rect other)` is built-in and evaluates if two rectangles intersect.

---

## 3. Drafted Dart Helper Methods & Merging Logic

We propose adding the merging logic as a dedicated utility class `OcrBlockMerger` inside `lib/ocr_service.dart`.

### Three-Phase Merging Design
To ensure stable and correct grouping:
1.  **Phase 1: Overlaps**: Group and merge any blocks that directly intersect. This fixes raw OCR fragmented boxes.
2.  **Phase 2: Horizontal Alignment**: Merge same-line blocks (high vertical overlap, small horizontal gap). A heuristic is added: *Do not merge horizontally if both blocks are vertical lines (height > width)* to prevent separate Japanese vertical columns from mixing.
3.  **Phase 3: Vertical Alignment**: Merge paragraph lines and columns (high horizontal overlap, small vertical gap).

### Complete Dart Implementation Draft

```dart
import 'dart:math' as math;
import 'dart:ui';

/// Custom text block representation to support merging.
class OcrBlock {
  final String text;
  final Rect boundingBox;

  OcrBlock({
    required this.text,
    required this.boundingBox,
  });
}

/// Helper utility to merge fragmented OCR blocks.
class OcrBlockMerger {
  /// Checks if two rectangles overlap.
  static bool rectsOverlap(Rect a, Rect b) {
    return a.overlaps(b);
  }

  /// Calculates the union bounding box of two rectangles.
  static Rect mergeRects(Rect a, Rect b) {
    return Rect.fromLTRB(
      math.min(a.left, b.left),
      math.min(a.top, b.top),
      math.max(a.right, b.right),
      math.max(a.bottom, b.bottom),
    );
  }

  /// Checks if two blocks are horizontally aligned (same text line).
  static bool areHorizontallyAligned(
    Rect a,
    Rect b, {
    double verticalOverlapThreshold = 0.5,
    double maxHorizontalGap = 30.0,
  }) {
    // 1. Calculate vertical overlap
    final overlapY = math.max(0.0, math.min(a.bottom, b.bottom) - math.max(a.top, b.top));
    final minHeight = math.min(a.height, b.height);
    if (minHeight == 0) return false;

    final overlapFraction = overlapY / minHeight;
    if (overlapFraction < verticalOverlapThreshold) return false;

    // 2. Prevent horizontal merging of vertical text columns
    final isAVertical = a.height > a.width;
    final isBVertical = b.height > b.width;
    if (isAVertical && isBVertical) {
      return false; // Both are vertical text columns; do not merge horizontally
    }

    // 3. Calculate horizontal gap
    final gapX = a.left < b.left ? b.left - a.right : a.left - b.right;
    return gapX <= maxHorizontalGap;
  }

  /// Checks if two blocks are vertically aligned (consecutive lines / same column).
  static bool areVerticallyAligned(
    Rect a,
    Rect b, {
    double horizontalOverlapThreshold = 0.5,
    double maxVerticalGap = 25.0,
  }) {
    // 1. Calculate horizontal overlap
    final overlapX = math.max(0.0, math.min(a.right, b.right) - math.max(a.left, b.left));
    final minWidth = math.min(a.width, b.width);
    if (minWidth == 0) return false;

    final overlapFraction = overlapX / minWidth;
    if (overlapFraction < horizontalOverlapThreshold) return false;

    // 2. Calculate vertical gap
    final gapY = a.top < b.top ? b.top - a.bottom : a.top - b.bottom;
    return gapY <= maxVerticalGap;
  }

  /// Merges two blocks and orders text based on alignment.
  static OcrBlock mergeBlocks(OcrBlock a, OcrBlock b) {
    final mergedBox = mergeRects(a.boundingBox, b.boundingBox);
    String mergedText;

    // Determine if they are primarily horizontally aligned
    final overlapY = math.max(0.0, math.min(a.boundingBox.bottom, b.boundingBox.bottom) - math.max(a.boundingBox.top, b.boundingBox.top));
    final minHeight = math.min(a.boundingBox.height, b.boundingBox.height);
    final isHorizontal = minHeight > 0 && (overlapY / minHeight) >= 0.5;

    // Check if either block is vertical to avoid horizontal sort layout confusion
    final isAVertical = a.boundingBox.height > a.boundingBox.width;
    final isBVertical = b.boundingBox.height > b.boundingBox.width;
    final forceVertical = isAVertical && isBVertical;

    if (isHorizontal && !forceVertical) {
      // Sort horizontally (left-to-right)
      if (a.boundingBox.left < b.boundingBox.left) {
        mergedText = _concatenateText(a.text, b.text, isHorizontal: true);
      } else {
        mergedText = _concatenateText(b.text, a.text, isHorizontal: true);
      }
    } else {
      // Sort vertically (top-to-bottom)
      if (a.boundingBox.top < b.boundingBox.top) {
        mergedText = _concatenateText(a.text, b.text, isHorizontal: false);
      } else {
        mergedText = _concatenateText(b.text, a.text, isHorizontal: false);
      }
    }

    return OcrBlock(
      text: mergedText,
      boundingBox: mergedBox,
    );
  }

  /// Iteratively groups and merges blocks using the three phases.
  static List<OcrBlock> merge(
    List<OcrBlock> blocks, {
    double verticalOverlapThreshold = 0.5,
    double maxHorizontalGap = 30.0,
    double horizontalOverlapThreshold = 0.5,
    double maxVerticalGap = 25.0,
  }) {
    if (blocks.isEmpty) return [];

    List<OcrBlock> result = List.from(blocks);

    // Phase 1: Overlaps
    result = _mergePhase(
      result,
      (a, b) => rectsOverlap(a.boundingBox, b.boundingBox),
    );

    // Phase 2: Horizontal Alignment
    result = _mergePhase(
      result,
      (a, b) => areHorizontallyAligned(
        a.boundingBox,
        b.boundingBox,
        verticalOverlapThreshold: verticalOverlapThreshold,
        maxHorizontalGap: maxHorizontalGap,
      ),
    );

    // Phase 3: Vertical Alignment
    result = _mergePhase(
      result,
      (a, b) => areVerticallyAligned(
        a.boundingBox,
        b.boundingBox,
        horizontalOverlapThreshold: horizontalOverlapThreshold,
        maxVerticalGap: maxVerticalGap,
      ),
    );

    return result;
  }

  /// Helper to run a single phase of merging.
  static List<OcrBlock> _mergePhase(
    List<OcrBlock> blocks,
    bool Function(OcrBlock a, OcrBlock b) shouldMerge,
  ) {
    List<OcrBlock> workingList = List.from(blocks);
    bool mergedAny = true;

    while (mergedAny) {
      mergedAny = false;
      int indexA = -1;
      int indexB = -1;

      for (int i = 0; i < workingList.length; i++) {
        for (int j = i + 1; j < workingList.length; j++) {
          if (shouldMerge(workingList[i], workingList[j])) {
            indexA = i;
            indexB = j;
            mergedAny = true;
            break;
          }
        }
        if (mergedAny) break;
      }

      if (mergedAny) {
        final a = workingList[indexA];
        final b = workingList[indexB];
        final merged = mergeBlocks(a, b);

        workingList.removeAt(indexB);
        workingList.removeAt(indexA);
        workingList.add(merged);
      }
    }
    return workingList;
  }

  /// Smart text concatenation handles spacing between alphabetic characters and CJK.
  static String _concatenateText(String first, String second, {required bool isHorizontal}) {
    if (first.isEmpty) return second;
    if (second.isEmpty) return first;

    if (isHorizontal) {
      final lastCharOfFirst = first.codeUnitAt(first.length - 1);
      final firstCharOfSecond = second.codeUnitAt(0);

      final isFirstCjk = _isCjkCodePoint(lastCharOfFirst);
      final isSecondCjk = _isCjkCodePoint(firstCharOfSecond);

      // Concatenate directly without space if either side is CJK
      if (isFirstCjk || isSecondCjk) {
        return first + second;
      } else {
        return '$first $second';
      }
    } else {
      return '$first\n$second';
    }
  }

  /// Determines if a character is CJK (Japanese/Chinese/Korean) script or symbol.
  static bool _isCjkCodePoint(int codePoint) {
    return (codePoint >= 0x4E00 && codePoint <= 0x9FFF) || // CJK Ideographs
           (codePoint >= 0x3040 && codePoint <= 0x309F) || // Hiragana
           (codePoint >= 0x30A0 && codePoint <= 0x30FF) || // Katakana
           (codePoint >= 0x3000 && codePoint <= 0x303F) || // CJK Symbols & Punctuation
           (codePoint >= 0xFF00 && codePoint <= 0xFFEF);   // Halfwidth and Fullwidth Forms
  }
}
```

---

## 4. Current Test Suite and Designing New Unit Tests

### Current Test Suite Structure
*   **File**: `test/ocr_service_test.dart`
*   **Current Checks**: Only verifies compilation and non-null instantiation of `OcrService`:
    ```dart
    test('OcrService extracts text blocks', () async {
      final service = OcrService();
      expect(service, isNotNull);
    });
    ```

### Proposed New Unit Tests Location
New unit tests should be placed in `test/ocr_service_test.dart` inside a new `group('OCR Block Merging', ...)` block. Since the merging logic relies on pure Dart (`OcrBlock` and `Rect`), these unit tests can run successfully in a headless/mocked environment using `flutter test`.

### Proposed Unit Tests Implementation

```dart
group('OCR Block Merging Unit Tests', () {
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
```
