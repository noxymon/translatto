# Screenshot Status Bar Cropping Analysis

This report documents how screen capture is handled in the current Android implementation of the application and provides a detailed strategy for dynamically querying and cropping out the status bar height in Kotlin.

---

## 1. Where the Screenshot is Captured

The screenshot capture process is managed by `MediaProjectionService` using the Android **MediaProjection API**.

- **Initialization**: 
  In `MediaProjectionService.setupCaptureSession` (lines 84-144):
  - An `ImageReader` is instantiated with the screen's raw dimensions (`width`, `height`) and pixel format `PixelFormat.RGBA_8888` (line 126):
    ```kotlin
    imageReader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)
    ```
  - A `VirtualDisplay` is created via `MediaProjection.createVirtualDisplay` (lines 127-136), which mirrors the screen contents onto the `ImageReader`'s Surface:
    ```kotlin
    virtualDisplay = projection.createVirtualDisplay(
        "ScreenCapture",
        width, height, density,
        DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
        imageReader?.surface,
        null, null
    )
    ```

- **Capture Execution**:
  In `MediaProjectionService.captureScreenFrame` (lines 173-247):
  - Triggered by Flutter sending the `"captureScreen"` method call to `MainActivity` (line 60), which delegates it to `MediaProjectionService.instance.captureScreenFrame(result)`.
  - It attempts to fetch the latest frame using `imageReader.acquireLatestImage()` (line 215).
  - If a frame is not immediately available, it registers an `OnImageAvailableListener` (lines 220-241) to asynchronously capture the frame once the screen updates.
  - The captured `Image` is then passed to `processImageAndReply(image, result)` (lines 249-312) to extract the byte buffer, construct a `Bitmap`, compress it to a JPEG, and save it.

---

## 2. How Captured Image Dimensions are Returned to Flutter

The captured image dimensions and cached path are returned to Flutter within `processImageAndReply` (lines 249-312):

1. **Extracting Dimensions**:
   The dimensions are derived directly from the captured `Image` object (lines 255-256):
   ```kotlin
   val width = image.width
   val height = image.height
   ```
2. **Result Packaging**:
   Once the `Bitmap` is compressed and saved to a cached file (`screen_capture.jpg`), the path and the original `width` and `height` dimensions are mapped to a `HashMap<String, Any>` (lines 287-291):
   ```kotlin
   val reply = HashMap<String, Any>()
   reply["path"] = file.absolutePath
   reply["width"] = width
   reply["height"] = height
   ```
3. **Flutter Invocation**:
   This map is sent back via Flutter's `MethodChannel.Result` interface on the main thread (line 291):
   ```kotlin
   result.success(reply)
   ```

---

## 3. How to Query the Status Bar Height Dynamically in Android

There are two primary methods to query the status bar height dynamically in Android.

### Method A: Resource ID Lookup (Traditional & Robust)
This is the most reliable approach when running inside a background `Service` (such as `MediaProjectionService`), as it does not rely on window hierarchy focus or layout rendering. It uses the service's `Context` directly and handles density-to-pixel conversion automatically.

```kotlin
fun getStatusBarHeight(context: Context): Int {
    val resourceId = context.resources.getIdentifier("status_bar_height", "dimen", "android")
    return if (resourceId > 0) {
        context.resources.getDimensionPixelSize(resourceId)
    } else {
        0
    }
}
```
*Note*: `getDimensionPixelSize` returns the size in **physical pixels (px)**, matching the coordinate system used by the screenshot `Bitmap`.

### Method B: Window Insets API (Modern, Android 11 / API 30+)
For Android 11 (API 30) and above, the modern recommendation is to use the `WindowInsets` API. This can query the height of the status bar area explicitly. However, it requires an `Activity` context (which can be obtained via `MainActivity.activeActivity`):

```kotlin
import android.view.WindowInsets
import android.os.Build

fun getStatusBarHeightModern(context: Context): Int {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        val activity = MainActivity.activeActivity ?: return 0
        val windowMetrics = activity.windowManager.currentWindowMetrics
        val insets = windowMetrics.windowInsets.getInsetsIgnoringVisibility(
            WindowInsets.Type.statusBars()
        )
        return insets.top
    }
    return 0
}
```

### Recommendation
For the service, **Method A** is recommended because it runs inside `MediaProjectionService` directly using `this` (the service context) without depending on `MainActivity` being active, visible, or non-null.

---

## 4. How to Crop the Top Status Bar Area off the Bitmap

To crop the status bar, we can use `Bitmap.createBitmap(source, x, y, width, height)`.

### Logic & Memory Management
We should only perform cropping if `statusBarHeight` is valid (greater than 0 and less than the bitmap's total height) and if cropping is actually requested. We must also recycle the temporary original bitmap to avoid memory leaks.

```kotlin
fun cropStatusBar(sourceBitmap: Bitmap, statusBarHeight: Int): Bitmap {
    val height = sourceBitmap.height
    val width = sourceBitmap.width

    // Safety checks: Make sure the crop height is valid
    if (statusBarHeight <= 0 || statusBarHeight >= height) {
        return sourceBitmap
    }

    val croppedHeight = height - statusBarHeight
    
    // Create cropped bitmap starting from x=0, y=statusBarHeight
    val croppedBitmap = Bitmap.createBitmap(
        sourceBitmap,
        0,
        statusBarHeight,
        width,
        croppedHeight
    )
    
    // Crucial: Recycle original bitmap to prevent memory leaks
    if (croppedBitmap != sourceBitmap) {
        sourceBitmap.recycle()
    }
    
    return croppedBitmap
}
```

### Integration in `MediaProjectionService.processImageAndReply`
This cropping step fits directly after the bitmap cleaning/row-padding correction logic (lines 269-275).

```kotlin
// 1. Initial cleanup of row padding
val cleanBitmap = if (rowPadding == 0) {
    bitmap
} else {
    val cropped = Bitmap.createBitmap(bitmap, 0, 0, width, height)
    bitmap.recycle()
    cropped
}

// 2. Fetch status bar height dynamically
val statusBarHeight = getStatusBarHeight(this)

// 3. Crop status bar (if valid)
val finalBitmap = if (statusBarHeight in 1 until cleanBitmap.height) {
    val cropped = Bitmap.createBitmap(
        cleanBitmap,
        0,
        statusBarHeight,
        cleanBitmap.width,
        cleanBitmap.height - statusBarHeight
    )
    cleanBitmap.recycle()
    cropped
} else {
    cleanBitmap
}

// 4. Compress finalBitmap and send dimensions (finalBitmap.width, finalBitmap.height) to Flutter.
```

### Key Considerations for Integration:
- **Dimension Return**: When passing the width and height back to Flutter, make sure to pass the cropped dimensions:
  ```kotlin
  reply["width"] = finalBitmap.width
  reply["height"] = finalBitmap.height
  ```
- **Conditional Cropping**: Since full-screen apps (like games or videos) might hide the status bar, we may want to allow Flutter to pass a flag (e.g., `cropStatusBar: true/false`) through the MethodChannel arguments to control whether cropping should occur.
