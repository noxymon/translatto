# Handoff Report - Milestone 1 Reviewer

## 1. Observation

Direct observations from `/Users/haikalannisa/Documents/Code/screen-translate/android/app/src/main/kotlin/id/web/noxymon/translatto/MediaProjectionService.kt`:

- **Observation 1 (Memory Allocation)**: In `processImageAndReply`, a screen-sized Bitmap is allocated:
  ```kotlin
  262:             val bitmap = Bitmap.createBitmap(
  263:                 width + padX,
  264:                 height,
  265:                 Bitmap.Config.ARGB_8888
  266:             )
  ```
- **Observation 2 (Exception Scope)**: The bitmap is processed within a general `try` block that ends at line 326:
  ```kotlin
  326:         } catch (e: Throwable) {
  327:             handler.post {
  328:                 isCapturing = false
  329:                 result.error("ERROR", "Failed to process image: ${e.message}", null)
  330:             }
  331:         } finally {
  332:             image.close()
  333:         }
  ```
  Neither the catch block nor the finally block contains any calls to `bitmap.recycle()` or `cleanBitmap.recycle()`.
- **Observation 3 (Dynamic Lookup)**: The status bar height is fetched dynamically via:
  ```kotlin
  277:             val resourceId = resources.getIdentifier("status_bar_height", "dimen", "android")
  278:             val statusBarHeight = if (resourceId > 0) resources.getDimensionPixelSize(resourceId) else 0
  ```
- **Observation 4 (Cropping Logic)**: The bitmap is cropped starting at coordinate `y = statusBarHeight` unconditionally:
  ```kotlin
  281:                 val cropped = Bitmap.createBitmap(
  282:                     cleanBitmap,
  283:                     0,
  284:                     statusBarHeight,
  285:                     cleanBitmap.width,
  286:                     cleanBitmap.height - statusBarHeight
  287:                 )
  ```
- **Observation 5 (Coordinates Return)**: The coordinates returned to Flutter do not contain the Y-offset (`statusBarHeight`):
  ```kotlin
  309:                         val reply = HashMap<String, Any>()
  310:                         reply["path"] = file.absolutePath
  311:                         reply["width"] = finalWidth
  312:                         reply["height"] = finalHeight
  313:                         result.success(reply)
  ```
- **Observation 6 (Build Status)**: Running `./gradlew assembleDebug` in the `/Users/haikalannisa/Documents/Code/screen-translate/android` directory completed successfully with `BUILD SUCCESSFUL`.

## 2. Logic Chain

- **Step 1 (Memory Leak)**: From Observation 1 and 2, if an exception is thrown during execution of the `try` block (for example, inside `Bitmap.createBitmap` on line 281), the code jumps directly to line 326. Since no recycling logic is defined for `bitmap` or `cleanBitmap` in the catch/finally blocks, the allocated bitmap is leaked in the graphics heap.
- **Step 2 (Landscape Crop Issue)**: From Observation 3 and 4, the code uses a static `status_bar_height` resource ID and crops `statusBarHeight` from the top of the image (y=0 to y=statusBarHeight). In Landscape orientation, the status bar might be on the side or hidden entirely. Cropping unconditionally from the top results in cutting off active user content while leaving the status bar uncropped.
- **Step 3 (API Robustness)**: From Observation 3, resource identifier lookups are static. They fail to reflect dynamic window changes (e.g. fullscreen/immersive mode, multi-window mode, split screen).
- **Step 4 (Coordinate Translation)**: From Observation 5, because the return map contains only `width` and `height`, and the crop happens at the top (`y = statusBarHeight`), the image coordinates are shifted by `statusBarHeight` compared to the screen. Without this value, the Flutter UI cannot reliably translate pixel coordinates back to full-screen overlays.

## 3. Caveats

- We did not dynamically run the app on a real device or emulator to test multi-window behaviour, orientation changes, or status bar height values across various Android vendor skins (e.g. MIUI, OneUI).
- We assume that the Flutter client expects the coordinates of overlays to align exactly with full-screen coordinates. If Flutter renders the overlay in a Safe Area that already excludes the status bar height, coordinate mapping might align under portrait mode but will still fail in landscape or fullscreen immersive modes.

## 4. Conclusion

The status bar cropping implementation compiles successfully. However, it requires changes due to three major flaws:
1. **Memory Safety**: Memory leaks occur if exception paths are hit inside `processImageAndReply` after the first bitmap creation.
2. **API Robustness & Landscape Crop**: Unconditional top-cropping using static resource identifier lookup fails in landscape and fullscreen immersive modes.
3. **Coordinate Integrity**: The returned Map lacks the Y-offset of the crop, making accurate coordinate translation impossible on the Flutter client.

**Verdict**: REQUEST_CHANGES

## 5. Verification Method

To verify these findings:
1. Run `./gradlew assembleDebug` inside `/Users/haikalannisa/Documents/Code/screen-translate/android` to confirm the project still builds.
2. Inspect the file `/Users/haikalannisa/Documents/Code/screen-translate/android/app/src/main/kotlin/id/web/noxymon/translatto/MediaProjectionService.kt` to check if exception handling/recycling, dynamic inset querying, landscape checks, and offset return values have been added.
