package id.web.noxymon.translatto

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "id.web.noxymon.translatto/capture"
    private val BRIDGE_CHANNEL_NAME = "id.web.noxymon.translatto/overlay_bridge"
    private val REQUEST_CODE = 1001
    private var pendingResult: MethodChannel.Result? = null
    private var mediaProjectionManager: MediaProjectionManager? = null
    
    private var isOverlayBridgeSetup = false
    private var mainFlutterEngine: FlutterEngine? = null

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
        mainFlutterEngine = flutterEngine
        
        // Setup bridge on main engine
        setupMainBridgeChannel(flutterEngine)

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
                "openApp" -> {
                    try {
                        val intent = Intent(this, MainActivity::class.java).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", "Failed to launch main app: ${e.message}", null)
                    }
                }
                "getDeviceBoard" -> {
                    result.success(android.os.Build.BOARD)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        setupOverlayBridgeIfNeeded()
    }

    override fun onStart() {
        super.onStart()
        setupOverlayBridgeIfNeeded()
    }

    private fun setupMainBridgeChannel(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, BRIDGE_CHANNEL_NAME).setMethodCallHandler { call, result ->
            if (call.method == "send") {
                Log.d("MainActivity", "[Bridge] Received message from Main: " + call.arguments)
                setupOverlayBridgeIfNeeded()
                val overlayEngine = FlutterEngineCache.getInstance().get("myCachedEngine")
                if (overlayEngine != null) {
                    val overlayChannel = MethodChannel(overlayEngine.dartExecutor.binaryMessenger, BRIDGE_CHANNEL_NAME)
                    overlayChannel.invokeMethod("onMessage", call.arguments)
                    result.success(null)
                } else {
                    Log.w("MainActivity", "[Bridge] Overlay engine not cached during send from Main")
                    result.error("NO_OVERLAY", "Overlay engine not cached", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun setupOverlayBridgeIfNeeded() {
        if (isOverlayBridgeSetup) return
        val overlayEngine = FlutterEngineCache.getInstance().get("myCachedEngine")
        if (overlayEngine == null) {
            Log.d("MainActivity", "[Bridge] Overlay engine not found in cache yet")
            return
        }

        val appContext = applicationContext
        Log.d("MainActivity", "[Bridge] Setting up overlay bridge on cached overlay engine")
        val overlayChannel = MethodChannel(overlayEngine.dartExecutor.binaryMessenger, BRIDGE_CHANNEL_NAME)
        overlayChannel.setMethodCallHandler { call, result ->
            if (call.method == "send") {
                Log.d("MainActivity", "[Bridge] Received message from Overlay: " + call.arguments)
                if (call.arguments == "open_app") {
                    try {
                        val intent = appContext.packageManager.getLaunchIntentForPackage(appContext.packageName)?.apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                        } ?: Intent(appContext, MainActivity::class.java).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                        }
                        appContext.startActivity(intent)
                        result.success(null)
                    } catch (e: Exception) {
                        Log.e("MainActivity", "[Bridge] Failed to launch main app: " + e.message)
                        result.error("ERROR", "Failed to launch main app: " + e.message, null)
                    }
                    return@setMethodCallHandler
                }

                val mainEngine = mainFlutterEngine
                if (mainEngine != null) {
                    val mainChannel = MethodChannel(mainEngine.dartExecutor.binaryMessenger, BRIDGE_CHANNEL_NAME)
                    mainChannel.invokeMethod("onMessage", call.arguments)
                    result.success(null)
                } else {
                    Log.e("MainActivity", "[Bridge] Main engine is null when Overlay sent message: " + call.arguments)
                    result.error("NO_MAIN", "Main engine not available", null)
                }
            } else {
                result.notImplemented()
            }
        }
        isOverlayBridgeSetup = true
        Log.i("MainActivity", "[Bridge] Overlay bridge setup complete")
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
        isOverlayBridgeSetup = false
        mainFlutterEngine = null
        super.onDestroy()
    }
}
