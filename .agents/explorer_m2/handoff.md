# Handoff Report: OCR Block Merging

## 1. Observation
*   **File Path**: `lib/ocr_service.dart` (lines 6-10) defines `extractText`:
    ```dart
    Future<List<TextBlock>> extractText(String imagePath) async {
      final inputImage = InputImage.fromFilePath(imagePath);
      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);
      return recognizedText.blocks;
    }
    ```
*   **File Path**: `lib/main.dart` (lines 93, 100-104, 109-118) contains the only call and usage of `extractText`:
    ```dart
    final ocrBlocks = await _ocrService.extractText(path);
    ...
    final blockRecords = ocrBlocks.map((b) => (
      text: b.text,
      x: b.boundingBox.left.toInt(),
      y: b.boundingBox.top.toInt(),
    )).toList();
    ```
*   **File Path**: `test/ocr_service_test.dart` (lines 5-9) contains a basic compiler verification test:
    ```dart
    test('OcrService extracts text blocks', () async {
      // Standard mock test structure for compiler check
      final service = OcrService();
      expect(service, isNotNull);
    });
    ```
*   **External Dependency**: `google_mlkit_text_recognition` defines `TextBlock`, which has no public constructors for mock/manual creation of blocks on the Dart side, making custom `TextBlock` instances impossible to construct for tests or merging.
*   **Run Results**: Running `flutter test` completes successfully with all 16 tests passing.

---

## 2. Logic Chain
1.  **Limitation of `TextBlock`**: Since native `TextBlock` objects cannot be instantiated from Dart, we cannot return new merged blocks as `TextBlock` (Observation 4).
2.  **Introduction of `OcrBlock`**: Creating a simple wrapper class `OcrBlock` containing `text` and `boundingBox` (Rect) solves this constructor limitation.
3.  **Minimal Impact**: Since `lib/main.dart` relies on type inference (`final ocrBlocks = ...`) and only accesses `text` and `boundingBox` (Observation 2), updating `extractText` to return `List<OcrBlock>` compiles with zero downstream caller changes.
4.  **Three-Phase Merging Approach**: By splitting merging into sequential phases (Overlap, Horizontal same-line, Vertical consecutive-line), we avoid layout ambiguity.
5.  **CJK and Layout Heuristics**: 
    *   To keep columns separate in vertical Japanese layout, we do not horizontally merge blocks where both have `height > width`.
    *   To match natural text, we omit spaces at boundaries when merging Japanese/CJK text blocks, but preserve spaces for English/alphabetic characters.
6.  **Pure Dart Verification**: Since `OcrBlock` and `Rect` are pure Dart structures, we can test the entire merging logic in `test/ocr_service_test.dart` using standard unit tests (Observation 3).

---

## 3. Caveats
*   **Image Dimensions and Scale**: The pixel thresholds (`maxHorizontalGap: 30.0` and `maxVerticalGap: 25.0`) assume standard screenshot densities. If screen dimensions are very small or extremely large, the constant pixel values may need to be scaled relative to the text block heights.
*   **Mixed Vertical/Horizontal Layouts**: Highly complex multi-column vertical layouts with inline horizontal annotations may require further tuning of overlap thresholds.

---

## 4. Conclusion
We can implement OCR Block Merging successfully by:
1.  Creating an `OcrBlock` class in `lib/ocr_service.dart`.
2.  Refactoring `OcrService.extractText` to return `Future<List<OcrBlock>>` and internally calling `OcrBlockMerger.merge()`.
3.  Adding the `OcrBlockMerger` logic (drafted in `analysis.md`).
4.  Adding the drafted unit tests in `test/ocr_service_test.dart` to verify logic completely.

No changes to `lib/main.dart` or other services are needed for compilation.

---

## 5. Verification Method
1.  **Verify compilation and existing tests**:
    ```bash
    flutter test
    ```
2.  **Verify file paths and changes**:
    *   Inspect `lib/ocr_service.dart` to ensure `OcrBlock` and `OcrBlockMerger` are implemented.
    *   Inspect `test/ocr_service_test.dart` to confirm the new test group runs and passes.
3.  **Invalidation Conditions**: If `flutter test` fails, check if the dependencies or mock configurations in the project have changed.
