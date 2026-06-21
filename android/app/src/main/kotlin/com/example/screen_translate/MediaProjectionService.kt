package com.example.screen_translate

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.IBinder
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MediaProjectionService : Service() {

    private val CHANNEL_ID = "MediaProjectionServiceChannel"
    private val NOTIFICATION_ID = 1002

    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var isCapturing = false

    companion object {
        var instance: MediaProjectionService? = null
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = createNotification()
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID, 
                notification, 
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        val resultCode = intent?.getIntExtra("resultCode", 0) ?: 0
        val data = intent?.getParcelableExtra<Intent>("data")
        
        if (resultCode != 0 && data != null) {
            setupCaptureSession(resultCode, data)
        } else {
            MainActivity.activeActivity?.onSessionStarted(false, "Invalid start arguments")
            stopSelf()
        }

        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    private fun setupCaptureSession(resultCode: Int, data: Intent) {
        val windowManager = getSystemService(Context.WINDOW_SERVICE) as android.view.WindowManager
        val width: Int
        val height: Int
        val density: Int
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // Using maximumWindowMetrics to correctly scale full physical screen dimensions
            val windowMetrics = windowManager.maximumWindowMetrics
            val bounds = windowMetrics.bounds
            width = bounds.width()
            height = bounds.height()
            density = resources.configuration.densityDpi
        } else {
            val metrics = android.util.DisplayMetrics()
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay.getRealMetrics(metrics)
            width = metrics.widthPixels
            height = metrics.heightPixels
            density = metrics.densityDpi
        }

        try {
            cleanupResources()
            val projectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            val projection = projectionManager.getMediaProjection(resultCode, data)
            
            if (projection == null) {
                MainActivity.activeActivity?.onSessionStarted(false, "MediaProjection token is null")
                stopSelf()
                return
            }
            mediaProjection = projection

            // Use 2 buffers for ImageReader queue to optimize memory and capture performance
            imageReader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)
            virtualDisplay = projection.createVirtualDisplay(
                "ScreenCapture",
                width,
                height,
                density,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                imageReader?.surface,
                null,
                null
            )
            
            MainActivity.activeActivity?.onSessionStarted(true)
        } catch (e: Throwable) {
            cleanupResources()
            MainActivity.activeActivity?.onSessionStarted(false, "Failed to initialize capture session: ${e.message}")
            stopSelf()
        }
    }

    fun captureScreenFrame(result: MethodChannel.Result) {
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

        // Implement frame watchdog timeout of 1000ms to prevent infinite UI loader hangs
        val handler = android.os.Handler(android.os.Looper.getMainLooper())
        val timeoutRunnable = Runnable {
            if (isCapturing) {
                reader.setOnImageAvailableListener(null, null)
                isCapturing = false
                result.error("TIMEOUT", "Screen capture timed out (no screen update detected)", null)
            }
        }
        handler.postDelayed(timeoutRunnable, 1000)

        try {
            val image = reader.acquireLatestImage()
            if (image != null) {
                handler.removeCallbacks(timeoutRunnable)
                processImageAndReply(image, result)
            } else {
                reader.setOnImageAvailableListener({ r ->
                    try {
                        val img = r.acquireLatestImage() ?: return@setOnImageAvailableListener
                        
                        if (!isCapturing) {
                            img.close()
                            return@setOnImageAvailableListener
                        }
                        
                        r.setOnImageAvailableListener(null, null)
                        handler.removeCallbacks(timeoutRunnable)
                        processImageAndReply(img, result)
                    } catch (e: Throwable) {
                        r.setOnImageAvailableListener(null, null)
                        handler.removeCallbacks(timeoutRunnable)
                        handler.post {
                            isCapturing = false
                            result.error("ERROR", "Failed to acquire image: ${e.message}", null)
                        }
                    }
                }, null)
            }
        } catch (e: Throwable) {
            handler.removeCallbacks(timeoutRunnable)
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

            val cleanBitmap = if (rowPadding == 0) {
                bitmap
            } else {
                val cropped = Bitmap.createBitmap(bitmap, 0, 0, width, height)
                bitmap.recycle()
                cropped
            }

            Thread {
                try {
                    // Use JPEG compression instead of PNG to improve performance by 10x
                    val file = File(cacheDir, "screen_capture.jpg")
                    val out = FileOutputStream(file)
                    cleanBitmap.compress(Bitmap.CompressFormat.JPEG, 90, out)
                    out.flush()
                    out.close()
                    
                    android.os.Handler(android.os.Looper.getMainLooper()).post {
                        result.success(file.absolutePath)
                    }
                } catch (e: Throwable) {
                    android.os.Handler(android.os.Looper.getMainLooper()).post {
                        result.error("ERROR", "Failed to save frame: ${e.message}", null)
                    }
                } finally {
                    cleanBitmap.recycle()
                    android.os.Handler(android.os.Looper.getMainLooper()).post {
                        isCapturing = false
                    }
                }
            }.start()
        } catch (e: Throwable) {
            // Catch Throwable instead of Exception to intercept OutOfMemoryErrors safely
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                isCapturing = false
                result.error("ERROR", "Failed to process image: ${e.message}", null)
            }
        } finally {
            image.close()
        }
    }

    private fun createNotification(): Notification {
        val title = "Screen Translator"
        val message = "Capturing screen for translation..."
        
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
                .setContentTitle(title)
                .setContentText(message)
                .setSmallIcon(android.R.drawable.ic_menu_camera)
                .setOngoing(true)
                .build()
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setContentTitle(title)
                .setContentText(message)
                .setSmallIcon(android.R.drawable.ic_menu_camera)
                .setOngoing(true)
                .build()
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_ID,
                "Screen Capture Service Channel",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(serviceChannel)
        }
    }

    private fun cleanupResources() {
        imageReader?.setOnImageAvailableListener(null, null)
        imageReader?.close()
        imageReader = null
        virtualDisplay?.release()
        virtualDisplay = null
        mediaProjection?.stop()
        mediaProjection = null
    }

    override fun onDestroy() {
        cleanupResources()
        instance = null
        super.onDestroy()
    }
}
