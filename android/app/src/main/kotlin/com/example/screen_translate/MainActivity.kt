package com.example.screen_translate

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
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
    private var isCapturing = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        mediaProjectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startCaptureSession" -> {
                    pendingResult?.error("CANCELLED", "Overwritten by concurrent request", null)
                    pendingResult = result
                    
                    if (mediaProjection != null) {
                        result.success(true)
                        pendingResult = null
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
                "captureScreen" -> {
                    captureScreenFrame(result)
                }
                "stopCaptureSession" -> {
                    cleanupResources()
                    result.success(true)
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
            val pending = pendingResult
            if (resultCode == Activity.RESULT_OK && data != null && pending != null) {
                try {
                    // Start foreground service before retrieving MediaProjection token for Android 14+ compliance
                    val serviceIntent = Intent(this, MediaProjectionService::class.java)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(serviceIntent)
                    } else {
                        startService(serviceIntent)
                    }

                    mediaProjection = mediaProjectionManager?.getMediaProjection(resultCode, data)
                    if (mediaProjection == null) {
                        stopService(serviceIntent)
                        pending.error("ERROR", "MediaProjection is null", null)
                        pendingResult = null
                        return
                    }

                    setupCaptureSession(pending)
                } catch (e: Exception) {
                    val serviceIntent = Intent(this, MediaProjectionService::class.java)
                    stopService(serviceIntent)
                    pending.error("ERROR", "Failed to init MediaProjection: ${e.message}", null)
                    pendingResult = null
                }
            } else {
                pending?.error("CANCELLED", "Screen capture permission denied", null)
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
        
        try {
            val serviceIntent = Intent(this, MediaProjectionService::class.java)
            stopService(serviceIntent)
        } catch (e: Exception) {
            // Ignore service stop failure
        }
    }

    private fun setupCaptureSession(result: MethodChannel.Result) {
        val width: Int
        val height: Int
        val density: Int
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val windowMetrics = windowManager.currentWindowMetrics
            val bounds = windowMetrics.bounds
            width = bounds.width()
            height = bounds.height()
            density = resources.configuration.densityDpi
        } else {
            val metrics = DisplayMetrics()
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay.getRealMetrics(metrics)
            width = metrics.widthPixels
            height = metrics.heightPixels
            density = metrics.densityDpi
        }

        try {
            cleanupFrameResources()
            // Set maxImages = 2 for buffering
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
            result.success(true)
            pendingResult = null
        } catch (e: Exception) {
            cleanupResources()
            result.error("ERROR", "Failed to create virtual display: ${e.message}", null)
            pendingResult = null
        }
    }

    private fun captureScreenFrame(result: MethodChannel.Result) {
        val reader = imageReader
        if (reader == null) {
            result.error("ERROR", "Capture session not active", null)
            return
        }

        if (isCapturing) {
            result.error("BUSY", "Another capture is already in progress", null)
            return
        }
        isCapturing = true

        try {
            val image = reader.acquireLatestImage()
            if (image != null) {
                processImageAndReply(image, result)
            } else {
                reader.setOnImageAvailableListener({ r ->
                    try {
                        val img = r.acquireLatestImage()
                        if (img != null) {
                            r.setOnImageAvailableListener(null, null)
                            processImageAndReply(img, result)
                        }
                    } catch (e: Exception) {
                        r.setOnImageAvailableListener(null, null)
                        runOnUiThread {
                            isCapturing = false
                            result.error("ERROR", "Failed to acquire image: ${e.message}", null)
                        }
                    }
                }, null)
            }
        } catch (e: Exception) {
            isCapturing = false
            result.error("ERROR", "Failed to capture frame: ${e.message}", null)
        }
    }

    private fun processImageAndReply(image: Image, result: MethodChannel.Result) {
        try {
            val planes = image.planes
            val buffer = planes[0].buffer
            val pixelStride = planes[0].pixelStride
            val rowStride = planes[0].rowStride
            val width = image.width
            val height = image.height
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
                        result.success(file.absolutePath)
                    }
                } catch (e: Exception) {
                    runOnUiThread {
                        result.error("ERROR", "Failed to save frame: ${e.message}", null)
                    }
                } finally {
                    cleanBitmap.recycle()
                    runOnUiThread {
                        isCapturing = false
                    }
                }
            }.start()
        } catch (e: Exception) {
            runOnUiThread {
                isCapturing = false
                result.error("ERROR", "Failed to process image: ${e.message}", null)
            }
        } finally {
            image.close()
        }
    }

    override fun onDestroy() {
        cleanupResources()
        super.onDestroy()
    }
}
