import 'dart:math' as math;
import 'dart:ui';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrBlock {
  final String text;
  final Rect boundingBox;
  OcrBlock({required this.text, required this.boundingBox});
}

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
  /// [maxCharsPerBlock] prevents merged blocks from exceeding a character
  /// limit, which would overflow the LiteRT model's token budget and cause
  /// a DYNAMIC_UPDATE_SLICE crash.
  static List<OcrBlock> merge(
    List<OcrBlock> blocks, {
    double verticalOverlapThreshold = 0.5,
    double maxHorizontalGap = 30.0,
    double horizontalOverlapThreshold = 0.5,
    double maxVerticalGap = 25.0,
    int maxCharsPerBlock = 280,
  }) {
    if (blocks.isEmpty) return [];

    List<OcrBlock> result = List.from(blocks);

    // Phase 1: Overlaps
    result = _mergePhase(
      result,
      (a, b) => rectsOverlap(a.boundingBox, b.boundingBox),
      maxCharsPerBlock: maxCharsPerBlock,
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
      maxCharsPerBlock: maxCharsPerBlock,
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
      maxCharsPerBlock: maxCharsPerBlock,
    );

    return result;
  }

  /// Helper to run a single phase of merging.
  /// Skips any merge that would produce a block exceeding [maxCharsPerBlock].
  static List<OcrBlock> _mergePhase(
    List<OcrBlock> blocks,
    bool Function(OcrBlock a, OcrBlock b) shouldMerge, {
    int maxCharsPerBlock = 280,
  }) {
    List<OcrBlock> workingList = List.from(blocks);
    bool mergedAny = true;

    while (mergedAny) {
      mergedAny = false;
      int indexA = -1;
      int indexB = -1;

      for (int i = 0; i < workingList.length; i++) {
        for (int j = i + 1; j < workingList.length; j++) {
          if (shouldMerge(workingList[i], workingList[j])) {
            // Skip merge if combined text would exceed model token budget
            final combinedLen = workingList[i].text.length + workingList[j].text.length;
            if (combinedLen > maxCharsPerBlock) continue;
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

class OcrService {
  final _textRecognizer = TextRecognizer(script: TextRecognitionScript.japanese);

  Future<List<OcrBlock>> extractText(String imagePath) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);
    final ocrBlocks = recognizedText.blocks.map((b) => OcrBlock(
      text: b.text,
      boundingBox: b.boundingBox,
    )).toList();
    return OcrBlockMerger.merge(ocrBlocks);
  }

  void dispose() {
    _textRecognizer.close();
  }
}
