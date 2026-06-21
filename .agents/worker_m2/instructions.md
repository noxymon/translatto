# Worker Instructions - Milestone 2

You are the worker for Milestone 2: OCR Block Merging (Dart).
Your task is to implement OCR Block Merging inside `lib/ocr_service.dart` and add corresponding unit tests in `test/ocr_service_test.dart`.

## Requirements:
1. Define the custom `OcrBlock` class in `lib/ocr_service.dart`:
   ```dart
   import 'dart:ui';
   class OcrBlock {
     final String text;
     final Rect boundingBox;
     OcrBlock({required this.text, required this.boundingBox});
   }
   ```
2. Refactor `OcrService.extractText` to return `Future<List<OcrBlock>>`. Map native `TextBlock` lists to `OcrBlock` objects and pass them through the `OcrBlockMerger.merge` utility before returning.
3. Implement the `OcrBlockMerger` class with:
   - Phase 1: Overlaps merging.
   - Phase 2: Horizontal alignment merging.
     - Add a check to prevent horizontal merging if *both* blocks are vertical lines (height > width).
     - Handle spacing: concatenate CJK directly without spaces, but join other scripts with spaces.
   - Phase 3: Vertical alignment merging.
     - Separate lines with newlines `\n`.
4. Update `test/ocr_service_test.dart` to add a group of unit tests verifying all aspects of `OcrBlockMerger` (overlaps, horizontal/vertical alignment, vertical columns preservation, CJK spacing).
5. Verify that `flutter test test/ocr_service_test.dart` passes cleanly.

## Mandatory Integrity Warning
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A Forensic Auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.
