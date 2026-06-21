# Handoff Report: Screenshot Status Bar Cropping Investigation

## 1. Observation
- **Screenshot Capture Location**:
  In `/Users/haikalannisa/Documents/Code/screen-translate/android/app/src/main/kotlin/id/web/noxymon/translatto/MediaProjectionService.kt` under the function `captureScreenFrame(result: MethodChannel.Result)`:
  - An `ImageReader` instance (initialized at line 126 and created on line 156/157) holds the buffer mirroring the screen projection via `virtualDisplay` (line 127-136).
  - The frame is acquired at lines 215 and 222:
    ```kotlin
    val image = reader.acquireLatestImage()
    ```
- **Dimension Return Mechanism**:
  In `MediaProjectionService.kt` under `processImageAndReply(image: Image, result: MethodChannel.Result)`:
  - Lines 287-291 return the metadata to Flutter via MethodChannel:
    ```kotlin
    val reply = HashMap<String, Any>()
    reply["path"] = file.absolutePath
    reply["width"] = width
    reply["height"] = height
    result.success(reply)
    ```
- **Context Availability**:
  `MediaProjectionService` is a `Service` subclass (line 26) which acts as an Android `Context`, providing access to system resources.

---

## 2. Logic Chain
- **Screenshot Location**: From the `acquireLatestImage()` call (Observation 1), we establish that individual screenshots are grabbed from the `ImageReader` surface mirror.
- **Dimension Retrieval**: From Observation 2, the `reply` HashMap returns the exact image width and height parameters back to Flutter.
- **Status Bar Query**: Since the service extends `Context`, we can query resources dynamically using:
  ```kotlin
  val resourceId = resources.getIdentifier("status_bar_height", "dimen", "android")
  val statusBarHeight = if (resourceId > 0) resources.getDimensionPixelSize(resourceId) else 0
  ```
  This returns physical pixels which match the bitmap pixel coordinate space.
- **Cropping Operation**: To crop the status bar, we can use `Bitmap.createBitmap(cleanBitmap, 0, statusBarHeight, width, height - statusBarHeight)` which will output a sub-bitmap offset by the status bar's height. To prevent memory leaks, we must call `cleanBitmap.recycle()`.

---

## 3. Caveats
- **Fullscreen/Immersive Mode**: In fullscreen apps (like games/videos), the status bar might be hidden. Blind cropping would clip top UI elements.
- **Solution**: We should expose a control flag (`cropStatusBar: Boolean`) through the method channel invocation from Flutter or check visibility dynamically using `WindowInsets` on API 30+.

---

## 4. Conclusion
Dynamic status bar query and cropping can be fully implemented inside `MediaProjectionService` using standard resource dims and `Bitmap.createBitmap`, outputting the cropped dimensions back to Flutter via the existing MethodChannel reply layout.

---

## 5. Verification Method
- **Inspect Files**: Read `/Users/haikalannisa/Documents/Code/screen-translate/.agents/explorer_m1/analysis.md` for complete Kotlin snippets.
- **Build Verification**: Run `./gradlew assembleDebug` inside the `/Users/haikalannisa/Documents/Code/screen-translate/android` directory to verify there are no compilation errors after code modification.
