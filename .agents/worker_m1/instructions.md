# Worker Instructions - Milestone 1

You are the worker for Milestone 1: Screenshot Status Bar Cropping (Kotlin).
Your task is to modify `android/app/src/main/kotlin/id/web/noxymon/translatto/MediaProjectionService.kt` to crop the status bar height dynamically from screenshots.

## Requirements
1. Query the system status bar height in pixels dynamically using:
   ```kotlin
   val resourceId = resources.getIdentifier("status_bar_height", "dimen", "android")
   val statusBarHeight = if (resourceId > 0) resources.getDimensionPixelSize(resourceId) else 0
   ```
2. Crop the top `statusBarHeight` area off the screenshot bitmap before saving/compressing:
   - Create a cropped bitmap using `Bitmap.createBitmap`.
   - Recycle the temporary clean bitmap (if it is different from the cropped bitmap) to prevent memory leaks.
3. Use local variables for `finalWidth` and `finalHeight` of the cropped bitmap to safely return the updated dimensions in the MethodChannel reply map (avoid referencing recycled bitmap properties on the UI thread).
4. Verify the build compiles successfully without errors.

## Mandatory Integrity Warning
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A Forensic Auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.
