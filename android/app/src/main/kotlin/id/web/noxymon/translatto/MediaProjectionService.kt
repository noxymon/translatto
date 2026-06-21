package id.web.noxymon.translatto

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
import android.os.Handler
import android.os.IBinder
import android.os.Looper
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
    private val handler = Handler(Looper.getMainLooper())

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
        
        // Minor fix: Use API 33+ type-safe getParcelableExtra
        val data = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent?.getParcelableExtra("data", Intent::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent?.getParcelableExtra<Intent>("data")
        }
        
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
            
            // Important fix: Register a callback to stop the service cleanly if terminated from the system status bar
            projection.registerCallback(object : MediaProjection.Callback() {
                override fun onStop() {
                    cleanupResources()
                    stopSelf()
                }
            }, handler)
            
            mediaProjection = projection

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

    // Lazy display recreation helper on orientation/dimension change
    private fun checkAndRecreateDisplayIfNeeded(width: Int, height: Int) {
        val reader = imageReader ?: return
        if (reader.width != width || reader.height != height) {
            val density = resources.configuration.densityDpi
            try {
                imageReader?.setOnImageAvailableListener(null, null)
                imageReader?.close()
                virtualDisplay?.release()

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
            } catch (e: Throwable) {
                // Ignore failure on lazy recreation
            }
        }
    }

    fun captureScreenFrame(result: MethodChannel.Result) {
        val windowManager = getSystemService(Context.WINDOW_SERVICE) as android.view.WindowManager
        val currentWidth: Int
        val currentHeight: Int
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val windowMetrics = windowManager.maximumWindowMetrics
            val bounds = windowMetrics.bounds
            currentWidth = bounds.width()
            currentHeight = bounds.height()
        } else {
            val metrics = android.util.DisplayMetrics()
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay.getRealMetrics(metrics)
            currentWidth = metrics.widthPixels
            currentHeight = metrics.heightPixels
        }

        // Important fix: Recreate capture session if screen orientation/dimension changes
        checkAndRecreateDisplayIfNeeded(currentWidth, currentHeight)

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
        var bitmap: Bitmap? = null
        var cleanBitmap: Bitmap? = null
        var finalBitmap: Bitmap? = null
        var finalCropY = 0

        try {
            val planes = image.planes
            val buffer = planes[0].buffer
            val pixelStride = planes[0].pixelStride
            val rowStride = planes[0].rowStride
            val width = image.width
            val height = image.height
            
            // Minor fix: Wrap in defensive check to avoid division by zero
            val rowPadding = if (pixelStride > 0) rowStride - pixelStride * width else 0
            val padX = if (pixelStride > 0) rowPadding / pixelStride else 0

            bitmap = Bitmap.createBitmap(
                width + padX,
                height,
                Bitmap.Config.ARGB_8888
            )
            bitmap.copyPixelsFromBuffer(buffer)

            if (rowPadding == 0) {
                cleanBitmap = bitmap
            } else {
                cleanBitmap = Bitmap.createBitmap(bitmap, 0, 0, width, height)
                bitmap.recycle()
                bitmap = null
            }

            var statusBarHeight = 0
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    val windowManager = getSystemService(Context.WINDOW_SERVICE) as android.view.WindowManager
                    val windowInsets = windowManager.currentWindowMetrics.windowInsets
                    val insets = windowInsets.getInsets(android.view.WindowInsets.Type.statusBars())
                    statusBarHeight = insets.top
                } else {
                    val isLandscape = resources.configuration.orientation == android.content.res.Configuration.ORIENTATION_LANDSCAPE
                    if (isLandscape) {
                        statusBarHeight = 0
                    } else {
                        val resourceId = resources.getIdentifier("status_bar_height", "dimen", "android")
                        statusBarHeight = if (resourceId > 0) resources.getDimensionPixelSize(resourceId) else 0
                    }
                }
            } catch (e: Throwable) {
                try {
                    val resourceId = resources.getIdentifier("status_bar_height", "dimen", "android")
                    statusBarHeight = if (resourceId > 0) resources.getDimensionPixelSize(resourceId) else 0
                } catch (ex: Throwable) {
                    statusBarHeight = 0
                }
            }

            if (statusBarHeight > 0 && statusBarHeight < cleanBitmap.height) {
                try {
                    val cropped = Bitmap.createBitmap(
                        cleanBitmap,
                        0,
                        statusBarHeight,
                        cleanBitmap.width,
                        cleanBitmap.height - statusBarHeight
                    )
                    finalBitmap = cropped
                    finalCropY = statusBarHeight
                    if (cropped != cleanBitmap) {
                        cleanBitmap.recycle()
                        if (cleanBitmap == bitmap) {
                            bitmap = null
                        }
                        cleanBitmap = null
                    }
                } catch (e: Throwable) {
                    System.gc()
                    finalBitmap = cleanBitmap
                    finalCropY = 0
                }
            } else {
                finalBitmap = cleanBitmap
                finalCropY = 0
            }

            if (finalBitmap == null) {
                throw IllegalStateException("finalBitmap is null")
            }

            val finalWidth = finalBitmap.width
            val finalHeight = finalBitmap.height
            val threadBitmap = finalBitmap
            val threadCropY = finalCropY

            Thread {
                try {
                    val file = File(cacheDir, "screen_capture.jpg")
                    val out = FileOutputStream(file)
                    threadBitmap.compress(Bitmap.CompressFormat.JPEG, 90, out)
                    out.flush()
                    out.close()
                    
                    handler.post {
                        // Important fix: Return actual width/height map to guarantee exact AR alignment on rotation
                        val reply = HashMap<String, Any>()
                        reply["path"] = file.absolutePath
                        reply["width"] = finalWidth
                        reply["height"] = finalHeight
                        reply["cropY"] = threadCropY
                        result.success(reply)
                    }
                } catch (e: Throwable) {
                    handler.post {
                        result.error("ERROR", "Failed to save frame: ${e.message}", null)
                    }
                } finally {
                    threadBitmap.recycle()
                    handler.post {
                        isCapturing = false
                    }
                }
            }.start()
        } catch (e: Throwable) {
            bitmap?.recycle()
            if (cleanBitmap != bitmap) {
                cleanBitmap?.recycle()
            }
            if (finalBitmap != cleanBitmap && finalBitmap != bitmap) {
                finalBitmap?.recycle()
            }
            handler.post {
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
