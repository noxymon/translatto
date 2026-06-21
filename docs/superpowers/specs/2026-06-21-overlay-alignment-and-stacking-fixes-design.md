# Spec: Overlay Alignment, Block Stacking, and Capture Flow Fixes

**Date**: 2026-06-21  
**Status**: Approved (Brainstorming Complete)

---

## 1. Problem Description

During real-world translation testing of the Japanese-to-English screen translator on an Android device:
1. **Vertical Offset/Shift**: The overlay translation boxes were shifted vertically downwards relative to the underlying Japanese text, preventing precise in-place overlay.
2. **Japanese in Output**: Under certain conditions, translation blocks displayed the original Japanese text instead of English.
3. **FAB Captured in Screenshot**: Tapping the floating translate button captured the button itself (including its loading spinner) inside the screenshot, cluttering the OCR input.
4. **Stacked/Overlapping Boxes**: When English translations were longer than the original Japanese blocks, they expanded vertically and overlapped adjacent translation boxes, rendering the text unreadable.

---

## 2. Technical Specification

### 2.1. Coordinate Space Alignment (Status Bar Cropping)

The root cause of the vertical shift is a mismatch between the screenshot coordinate space and the overlay window coordinate space:
* **Screenshot**: Captures the entire physical display, including the top Android status bar (e.g., 24dp/72px height). Y=0 starts at the top edge of the physical screen.
* **Overlay Window**: Resides in a window constrained below the status bar. Y=0 starts at the bottom edge of the status bar.

#### Proposed Change:
Excludes the status bar from both the screenshot and the overlay coordinate scaling.
1. In `MediaProjectionService.kt`, query the system status bar height in pixels:
   ```kotlin
   val resourceId = resources.getIdentifier("status_bar_height", "dimen", "android")
   val statusBarHeight = if (resourceId > 0) resources.getDimensionPixelSize(resourceId) else 0
   ```
2. When copying and saving the screenshot frame, crop the top `statusBarHeight` area off the bitmap:
   ```kotlin
   val cropped = Bitmap.createBitmap(bitmap, 0, statusBarHeight, width, height - statusBarHeight)
   ```
3. Return the cropped dimensions (`width` and `height - statusBarHeight`) in the channel reply.
4. In Dart, the overlay window is resized to these cropped dimensions. Since both the cropped screenshot and the overlay window now share the exact same bounding area, coordinate scaling becomes a uniform `1 / devicePixelRatio` scale factor with zero offsets.

---

### 2.2. Preventing Block Stacking (OCR Bounding Box Merging)

ML Kit OCR returns individual text blocks. When paragraph lines or adjacent words are split into separate blocks, translating them individually causes:
- Low-quality, fragmented translations.
- Vertical expansion of English translations that overlap adjacent blocks.

#### Proposed Heuristic:
Before translating, we group and merge OCR blocks in Dart based on proximity and alignment:
1. **Overlap Check**: Merge blocks if they geometrically overlap:
   ```dart
   if (rectA.overlaps(rectB)) return true;
   ```
2. **Vertical Alignment (Paragraph Lines)**: Merge blocks that are stacked vertically if:
   - Their horizontal overlap is $\ge 30\%$ of the narrower block's width.
   - The vertical gap between them is $\le 1.5 \times$ the height of the shorter block.
3. **Horizontal Alignment (Adjacent Words)**: Merge blocks side-by-side if:
   - Their vertical overlap is $\ge 50\%$ of the shorter block's height.
   - The horizontal gap between them is $\le 2.0 \times$ the height of the shorter block.

#### Merging Action:
- Bounding Box: `rectA.expandToInclude(rectB)`
- Text: Join texts with a space: `"${b1.text} ${b2.text}"`

This consolidates fragmented segments into semantic paragraphs, which improves Gemma's translation output and prevents overlapping layout boxes.

---

### 2.3. FAB Visibility and Resize Sequence

To prevent the FAB trigger button from appearing in screenshots:
1. When the user clicks the FAB in `OverlayWindowScreen`, immediately set `_isTranslating = true`.
2. Resize the overlay window to `1x1` logical pixels (practically invisible and non-interactive):
   ```dart
   await FlutterOverlayWindow.resizeOverlay(1, 1, false);
   ```
3. Introduce a `100ms` transition delay to ensure the Android window manager has applied the resize and cleared the screen.
4. Trigger the screenshot capture channel:
   ```dart
   await OverlayBridge.send("capture");
   ```
5. Restore overlay dimensions:
   - **On Success**: Resize to full screen (`widthDp` by `heightDp`, no drag) and render the translated custom paint layer.
   - **On Error / No Text**: Resize back to `140x140` logical pixels, enable dragging, and show error toast feedback if applicable.

---

## 3. Verification & Testing

### 3.1. Unit Testing
- Create `test/block_merging_test.dart` to verify that the OCR block merging heuristics successfully combine overlapping, vertically stacked, and horizontally adjacent rectangles, and concatenate their text correctly.

### 3.2. Widget Testing
- Update `test/overlay_dismissal_test.dart` and `test/widget_test.dart` to verify that tapping the trigger FAB invokes `resizeOverlay(1, 1, false)` and restores back to `140x140` on errors or no-text states.

---

## 4. Rollout & Integration Plan
- Stage 1: Implement status bar cropping in Kotlin (`MediaProjectionService.kt`).
- Stage 2: Implement block-merging logic in Dart and add unit tests.
- Stage 3: Implement the 1x1 resize flow in the overlay screen and verify widget tests.
- Stage 4: Run full assembly APK builds and static analysis.
