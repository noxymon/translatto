# Code Review Report - Milestone 1

## Review Summary

**Verdict**: REQUEST_CHANGES

## Findings

### [Major] Finding 1: Memory Leak under Exception Paths
- **What**: Potential memory leak of screen-sized Bitmaps.
- **Where**: `MediaProjectionService.kt` inside `processImageAndReply` (lines 250–334).
- **Why**: The `bitmap` (and potentially `cleanBitmap`) are created on the main thread and passed to a background thread to be compressed and recycled. However, if an exception is thrown *before* starting the background thread (for example, if `Bitmap.createBitmap` on line 272 or line 281 fails due to `IllegalArgumentException` or `OutOfMemoryError`), execution jumps to the outer `catch` block (line 326). Neither `bitmap` nor `cleanBitmap` is recycled in this catch block, leading to a major leak of unmanaged graphics memory (~10MB per occurrence).
- **Suggestion**: Ensure that any allocated bitmaps are safely recycled in the `catch` block or using a `try-finally` structure for the bitmap creation/cropping phase.

### [Major] Finding 2: Missing Crop Y-Offset in Return Coordinates
- **What**: Cropped coordinates returned to Flutter do not specify the vertical offset.
- **Where**: `MediaProjectionService.kt` inside `processImageAndReply` (lines 309–314).
- **Why**: The method returns the cropped `width` and `height`, but does not return the vertical crop offset (`cropY` / `statusBarHeight`). Since the status bar is cropped from the top of the screen capture, all coordinates inside the cropped image are shifted vertically. Without returning the exact `statusBarHeight` or `cropY` offset used, the Flutter side cannot accurately map bounding box coordinates back to full-screen screen coordinates, causing misaligned AR/translation overlays.
- **Suggestion**: Add a `cropY` field to the returned HashMap indicating the offset (i.e. `statusBarHeight` or `0`).

### [Major] Finding 3: Unreliable / Static Status Bar Height Lookup
- **What**: Querying status bar height via Android resource ID reflection.
- **Where**: `MediaProjectionService.kt` (lines 277–278).
- **Why**: Using `resources.getIdentifier("status_bar_height", "dimen", "android")` retrieves a static dimension from resources. It does not account for window insets, split-screen/multi-window layouts, or immersive fullscreen states (where the status bar is hidden, but the resource ID still returns a non-zero height, leading to unnecessary top-cropping).
- **Suggestion**: On Android 11 (API 30) and above, query the actual window status bar insets dynamically using `WindowMetrics` and `WindowInsets.Type.statusBars()`.

---

## Verified Claims

- **Code Compiles** → Verified via `./gradlew assembleDebug` in `/Users/haikalannisa/Documents/Code/screen-translate/android` → **PASS** (Build finished successfully).
- **Returns Cropped Dimensions** → Verified by inspection of lines 296–314 → **PASS** (The actual dimensions of `finalBitmap` are returned).

---

## Coverage Gaps

- **Flutter Coordinate Mapping** — risk level: **High** — recommendation: Investigate how the Flutter client handles coordinate mapping. Check if the Flutter client currently assumes full-screen coordinates or has hardcoded offsets.

---

## Unverified Items

- **Actual Crop Accuracy on Real Devices** — Reason not verified: Emulators/devices with cutouts or notches were not run dynamically to verify visual alignment.

---

# Adversarial Review / Stress Test

## Challenge Summary

**Overall risk assessment**: MEDIUM to HIGH

## Challenges

### [Critical] Challenge 1: Landscape Orientation Crop Failure
- **Assumption challenged**: The status bar is always located at the top of the image and equals the portrait status bar height.
- **Attack scenario**: When the device is rotated to Landscape orientation, the status bar may move to the side (left/right) or be completely hidden. Querying `status_bar_height` will still return the portrait height or a static value, and the code will blindly crop `statusBarHeight` from the top of the image:
  ```kotlin
  val cropped = Bitmap.createBitmap(cleanBitmap, 0, statusBarHeight, cleanBitmap.width, cleanBitmap.height - statusBarHeight)
  ```
  This will delete valid screen content at the top and leave the status bar intact on the side/top, causing corrupted image capture and alignment.
- **Blast radius**: Completely breaks translation alignment and overlays in landscape mode.
- **Mitigation**: Detect device orientation and inset visibility before cropping. If in landscape or if the status bar is not visible/present, do not perform top cropping (or crop from the side as appropriate).

### [Medium] Challenge 2: Out of Memory (OOM) under pressure
- **Assumption challenged**: The system has enough memory to allocate multiple screen-sized Bitmaps.
- **Attack scenario**: When capturing a high-resolution screen (e.g. 1440p), `Bitmap.createBitmap` requires a continuous block of ~15MB of RAM. If multiple captures are initiated or if memory is fragmented, cropping will throw `OutOfMemoryError`.
- **Blast radius**: Service crashes or returns error.
- **Mitigation**: Wrap bitmap creation in `try-catch` checking for `OutOfMemoryError`, and proactively trigger `System.gc()` or reuse bitmaps where possible.
