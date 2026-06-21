# Worker Remedial Instructions - Milestone 1

You are the worker for the Milestone 1 Remediation.
Your task is to update `MediaProjectionService.kt` to address the following reviewer findings:

## Required Changes
1. **Memory Safety (OOM / Exception Leak)**:
   - Wrap bitmap allocations/manipulation in a `try-catch-finally` structure.
   - In the outer catch block of `processImageAndReply`, recycle `bitmap` and `cleanBitmap` if they are not null, to prevent memory leaks in case of exception paths.
   - Wrap `Bitmap.createBitmap` for cropping in a `try-catch` for `OutOfMemoryError` and other throwables. If it fails, run `System.gc()` and fall back to the uncropped `cleanBitmap`.
2. **API Robustness & Landscape Crop**:
   - Query status bar height dynamically. Use a `try-catch` block:
     - On API 30+ (Android 11+), use `windowManager.currentWindowMetrics.windowInsets.getInsets(android.view.WindowInsets.Type.statusBars()).top` to get the actual status bar height (this will return 0 if the status bar is hidden, e.g. in fullscreen/immersive mode).
     - On API < 30, check the device orientation: `resources.configuration.orientation == android.content.res.Configuration.ORIENTATION_LANDSCAPE`. If in Landscape, status bar height is 0. If in Portrait, use the resource identifier lookup (`status_bar_height`).
3. **Coordinate Integration**:
   - Save the crop offset in a local variable `finalCropY` (which is `statusBarHeight` if cropped, or `0` otherwise).
   - Return `"cropY"` in the MethodChannel reply Map along with `"path"`, `"width"`, and `"height"`.

## Mandatory Integrity Warning
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A Forensic Auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.
