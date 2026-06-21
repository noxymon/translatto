package com.example.screen_translate

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.util.DisplayMetrics
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.screentranslate/capture"
    private val REQUEST_CODE = 1001
    private var pendingResult: MethodChannel.Result? = null
    
    private var mediaProjectionManager: MediaProjectionManager? = null
    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        mediaProjectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "captureScreen" -> {
                    pendingResult?.error("CANCELLED", "Overwritten by concurrent request", null)
                    pendingResult = result
                    
                    if (mediaProjection != null) {
                        // Reuse active MediaProjection to prevent repetitive consent prompts and background activity blocks
                        captureScreenFrame(result)
                    } else {
                        val intent = mediaProjectionManager?.createScreenCaptureIntent()
                        if (intent != null) {
                            startActivityForResult(intent, REQUEST_CODE)
                        } else {
                            result.error("ERROR", "MediaProjection intent null", null)
                            pendingResult = null
                        }
                    }
                }
                "stopCaptureSession" -> {
                    cleanupResources()
                    result.success(null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CODE) {
            val result = pendingResult
            if (resultCode == Activity.RESULT_OK && data != null && result != null) {
                try {
                    mediaProjection = mediaProjectionManager?.getMediaProjection(resultCode, data)
                    if (mediaProjection == null) {
                        result.error("ERROR", "MediaProjection is null", null)
                        pendingResult = null
                        return
                    }
                    captureScreenFrame(result)
                } catch (e: Exception) {
                    result.error("ERROR", "Failed to init MediaProjection: ${e.message}", null)
                    pendingResult = null
                }
            } else {
                result?.error("CANCELLED", "Screen capture permission denied", null)
                pendingResult = null
            }
        }
    }

    private fun cleanupFrameResources() {
        imageReader?.setOnImageAvailableListener(null, null)
        imageReader?.close()
        imageReader = null
        virtualDisplay?.release()
        virtualDisplay = null
    }

    private fun cleanupResources() {
        cleanupFrameResources()
        mediaProjection?.stop()
        mediaProjection = null
    }

    private fun captureScreenFrame(result: MethodChannel.Result) {
        val metrics = DisplayMetrics()
        windowManager.defaultDisplay.getRealMetrics(metrics)
        val width = metrics.widthPixels
        val height = metrics.heightPixels
        val density = metrics.densityDpi

        try {
            imageReader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)
            virtualDisplay = mediaProjection?.createVirtualDisplay(
                "ScreenCapture",
                width,
                height,
                density,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                imageReader?.surface,
                null,
                null
            )

            imageReader?.setOnImageAvailableListener({ reader ->
                try {
                    val image = reader.acquireLatestImage()
                    if (image != null) {
                        try {
                            reader.setOnImageAvailableListener(null, null)
                            
                            val planes = image.planes
                            val buffer = planes[0].buffer
                            val pixelStride = planes[0].pixelStride
                            val rowStride = planes[0].rowStride
                            val rowPadding = rowStride - pixelStride * width

                            val bitmap = Bitmap.createBitmap(
                                width + rowPadding / pixelStride,
                                height,
                                Bitmap.Config.ARGB_8888
                            )
                            bitmap.copyPixelsFromBuffer(buffer)

                            val cleanBitmap = Bitmap.createBitmap(bitmap, 0, 0, width, height)
                            bitmap.recycle()

                            Thread {
                                try {
                                    val file = File(cacheDir, "screen_capture.png")
                                    val out = FileOutputStream(file)
                                    cleanBitmap.compress(Bitmap.CompressFormat.PNG, 90, out)
                                    out.flush()
                                    out.close()
                                    
                                    runOnUiThread {
                                        cleanupFrameResources()
                                        result.success(file.absolutePath)
                                    }
                                } catch (e: Exception) {
                                    runOnUiThread {
                                        cleanupFrameResources()
                                        result.error("ERROR", "Failed to save frame: ${e.message}", null)
                                    }
                                } finally {
                                    cleanBitmap.recycle()
                                    runOnUiThread {
                                        pendingResult = null
                                    }
                                }
                            }.start()
                        } finally {
                            // Guarantee native graphics Image buffer is closed to prevent leaks and hangs
                            image.close()
                        }
                    }
                } catch (e: Exception) {
                    runOnUiThread {
                        cleanupFrameResources()
                        result.error("ERROR", "Failed to capture frame: ${e.message}", null)
                        pendingResult = null
                    }
                }
            }, null)
        } catch (e: Exception) {
            cleanupFrameResources()
            result.error("ERROR", "Failed to initialize capture: ${e.message}", null)
            pendingResult = null
        }
    }

    override fun onDestroy() {
        cleanupResources()
        super.onDestroy()
    }
}
