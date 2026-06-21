# Orchestration Plan - screen-translate

This plan outlines the steps to implement screen layout alignment, OCR block merging, and overlay resizing state transitions.

## Milestones

### Milestone 1: Screenshot Status Bar Cropping (Kotlin)
- **Objective**: Dynamically fetch status bar height and crop the captured MediaProjection bitmap in Kotlin.
- **Tasks**:
  1. Explore `MediaProjectionService.kt` to understand how screenshot capturing and dimension reporting is implemented.
  2. Implement retrieval of `status_bar_height` dynamically via Android's resources dimension.
  3. Crop the captured Bitmap (top crop of status bar height).
  4. Ensure dimensions returned in the method channel reply match the cropped bitmap height.
- **Verification**:
  - Verification worker compiles the project and verifies Android build doesn't break.
  - Reviews and auditor checks.

### Milestone 2: OCR Block Merging (Dart)
- **Objective**: Merge OCR text blocks based on overlap and proximity/alignment thresholds.
- **Tasks**:
  1. Explore `ocr_service.dart` and existing OCR tests.
  2. Implement grouping and merging logic according to specification:
     - Geometrical overlap check: Merge if overlapping.
     - Vertical alignment: Horizontal overlap >= 30% of narrower block, vertical gap <= 1.5x height of shorter block.
     - Horizontal alignment: Vertical overlap >= 50% of shorter block, horizontal gap <= 2x height of shorter block.
     - Join text with space, expand bounding box.
  3. Implement unit tests in `test/block_merging_test.dart`.
- **Verification**:
  - Run `flutter test test/block_merging_test.dart` to verify correctness.

### Milestone 3: Resizing State Transitions (Dart)
- **Objective**: Resize overlay window to 1x1 before screenshot capture, introduce 100ms delay, and restore size on success/error.
- **Tasks**:
  1. Explore `lib/main.dart` and `lib/capture_service.dart` or overlay code to locate the capture flow and floating action button.
  2. Implement overlay resize to 1x1 pixels prior to screenshot capture.
  3. Introduce a 100ms delay after resize.
  4. Restore window size to full screen on success, or 140x140 on error/no-text.
  5. Write widget tests verifying the resize transition states.
- **Verification**:
  - Run all widget and unit tests to ensure they pass.

### Milestone 4: Integration Verification
- **Objective**: End-to-end verification of all integrated features.
- **Tasks**:
  1. Run `flutter analyze` to ensure zero errors, warnings, or lints.
  2. Run `flutter test` to ensure all tests pass.
  3. Conduct integrity forensics audit.
