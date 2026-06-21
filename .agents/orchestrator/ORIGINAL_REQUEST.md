# Original User Request

## Initial Request — 2026-06-21T20:12:01+09:00

Implement screen layout alignment, OCR block merging, and overlay resizing state fixes in the screen-translate application to ensure exact, overlap-free AR-style translations.

Working directory: /Users/haikalannisa/Documents/Code/screen-translate
Integrity mode: development

## Requirements

### R1. Screenshot Status Bar Cropping (Kotlin)
- The application must retrieve the system status bar height dynamically in Kotlin.
- The screenshot captured via MediaProjection must be cropped to exclude the top status bar area.
- The returned image dimensions must reflect the cropped height.

### R2. OCR Block Merging (Dart)
- Group and merge separate OCR blocks that represent lines of the same paragraph or adjacent words.
- Use proximity and alignment thresholds (using the approved design spec as a baseline, but allowing for tuning based on test cases).
- Combine their texts with spaces and wrap them in a single expanded bounding box.

### R3. Resizing State Transitions
- The overlay window must resize to 1x1 pixels before initiating the screen capture to prevent the FAB trigger from showing up in the screenshot.
- Introduce a short (100ms) delay after the 1x1 resize to allow the window transition to complete before capturing.
- Upon completion, the overlay window size must be restored to full screen (on success) or 140x140 (on error/no-text).

### R4. Automated Testing
- Implement unit tests for the OCR block-merging heuristics.
- Implement widget tests verifying the 1x1 resize transitions and restoration.

## Acceptance Criteria

### Correctness & Alignment
- [ ] Bounding boxes of translations are precisely aligned with original Japanese text positions (no status bar offset).
- [ ] The floating FAB trigger button is not visible in screenshots.
- [ ] Overlapping/stacked translation text boxes are eliminated.

### Test Coverage & Compilation
- [ ] Unit tests for block-merging verify correct concatenation and box expansion.
- [ ] Widget tests verify overlay resize calls for both successful and failed capture loops.
- [ ] `flutter test` completes successfully with all tests passing.
- [ ] `flutter analyze` reports zero errors, warnings, or lints.
