package com.foodfeast.app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val OVERLAY_CHANNEL = "com.foodfeast.app/native_overlay"
    private val OVERLAY_PERMISSION_REQUEST = 1001

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Your existing cutout plugin — unchanged
        DisplayCutoutPlugin.register(flutterEngine, this)

        // New: native overlay bridge
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            OVERLAY_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "showOverlay" -> {
                    val orderId = call.argument<String>("orderId") ?: ""
                    val status  = call.argument<String>("status")  ?: "pending"
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                        !Settings.canDrawOverlays(this)) {
                        startActivityForResult(
                            Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName")
                            ),
                            OVERLAY_PERMISSION_REQUEST
                        )
                        result.success(false)
                    } else {
                        DynamicIslandOverlayService.startOverlay(this, orderId, status)
                        result.success(true)
                    }
                }
                "dismissOverlay" -> {
                    DynamicIslandOverlayService.dismissOverlay(this)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Handle tap from native overlay when app is re-opened
        intent?.let { handleDeepIntent(it, flutterEngine) }
    }

    override fun onResume() {
        super.onResume()
        // Your existing MIUI fix — unchanged
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes.layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        flutterEngine?.let { handleDeepIntent(intent, it) }
    }

    private fun handleDeepIntent(intent: Intent, flutterEngine: FlutterEngine) {
        if (intent.getBooleanExtra("open_tracking", false)) {
            val orderId = intent.getStringExtra(DynamicIslandOverlayService.EXTRA_ORDER_ID) ?: return
            MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                OVERLAY_CHANNEL
            ).invokeMethod("onOverlayTapped", mapOf("orderId" to orderId))
        }
    }
}
