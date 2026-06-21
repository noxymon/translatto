package com.example.screen_translate

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.screentranslate/capture"
    private val REQUEST_CODE = 1001
    private var pendingResult: MethodChannel.Result? = null
    private var mediaProjectionManager: MediaProjectionManager? = null

    companion object {
        var activeActivity: MainActivity? = null
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        activeActivity = this
        mediaProjectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startCaptureSession" -> {
                    pendingResult?.error("CANCELLED", "Overwritten by concurrent request", null)
                    pendingResult = result
                    
                    if (MediaProjectionService.instance != null) {
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
                    val service = MediaProjectionService.instance
                    if (service != null) {
                        service.captureScreenFrame(result)
                    } else {
                        result.error("ERROR", "Capture session not active", null)
                    }
                }
                "stopCaptureSession" -> {
                    stopCaptureSessionService()
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
                    val serviceIntent = Intent(this, MediaProjectionService::class.java).apply {
                        putExtra("resultCode", resultCode)
                        putExtra("data", data)
                    }
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                        startForegroundService(serviceIntent)
                    } else {
                        startService(serviceIntent)
                    }
                } catch (e: Exception) {
                    pending.error("ERROR", "Failed to start MediaProjectionService: ${e.message}", null)
                    pendingResult = null
                }
            } else {
                pending?.error("CANCELLED", "Screen capture permission denied", null)
                pendingResult = null
            }
        }
    }

    fun onSessionStarted(success: Boolean, errorMsg: String? = null) {
        runOnUiThread {
            val pending = pendingResult
            if (pending != null) {
                if (success) {
                    pending.success(true)
                } else {
                    pending.error("ERROR", errorMsg ?: "Failed to start capture session", null)
                }
                pendingResult = null
            }
        }
    }

    private fun stopCaptureSessionService() {
        try {
            val serviceIntent = Intent(this, MediaProjectionService::class.java)
            stopService(serviceIntent)
        } catch (e: Exception) {
            // Ignore stop errors
        }
    }

    override fun onDestroy() {
        if (activeActivity == this) {
            activeActivity = null
        }
        super.onDestroy()
    }
}
