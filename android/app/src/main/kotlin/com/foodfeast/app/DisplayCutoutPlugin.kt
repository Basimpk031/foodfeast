package com.foodfeast.app

import android.os.Build
import android.util.Log
import android.view.DisplayCutout
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

object DisplayCutoutPlugin {

    private const val CHANNEL = "com.foodfeast.app/display_cutout"
    private const val TAG     = "DynamicIslandDebug"

    fun register(flutterEngine: FlutterEngine, activity: android.app.Activity) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            if (call.method == "getCutoutInfo") {
                val info = getCutoutInfo(activity)
                Log.d(TAG, "getCutoutInfo result: $info")
                result.success(info)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun getCutoutInfo(activity: android.app.Activity): Map<String, Any> {
        Log.d(TAG, "SDK_INT = ${Build.VERSION.SDK_INT}")

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            Log.d(TAG, "API < 28, returning none")
            return mapOf("type" to "none", "centerX" to 0.0, "screenW" to 0.0,
                         "cutoutH" to 0.0, "cutoutTop" to 0.0)
        }

        val screenW: Double = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activity.windowManager.currentWindowMetrics.bounds.width().toDouble()
        } else {
            val dm = android.util.DisplayMetrics()
            @Suppress("DEPRECATION")
            activity.windowManager.defaultDisplay.getMetrics(dm)
            dm.widthPixels.toDouble()
        }
        Log.d(TAG, "screenW = $screenW")

        val cutout: DisplayCutout? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activity.windowManager.currentWindowMetrics.windowInsets.displayCutout
        } else {
            @Suppress("DEPRECATION")
            activity.window.decorView.rootWindowInsets?.displayCutout
        }
        Log.d(TAG, "displayCutout from API = $cutout")

        if (cutout == null) {
            Log.d(TAG, "cutout is null — trying MIUI fallback")
            val miui = getMiuiCutoutRect(activity, screenW)
            Log.d(TAG, "MIUI result: $miui")
            return miui
        }

        val rects = cutout.boundingRects
        Log.d(TAG, "boundingRects = $rects")
        if (rects.isEmpty()) {
            Log.d(TAG, "rects is empty — returning none")
            return mapOf("type" to "none", "centerX" to 0.0, "screenW" to screenW,
                         "cutoutH" to 0.0, "cutoutTop" to 0.0)
        }

        // Pick the topmost rect (the camera cutout, not a bottom chin)
        val rect        = rects.minByOrNull { it.top }!!
        val centerX     = (rect.left + rect.right) / 2.0
        val cutoutW     = (rect.right  - rect.left).toDouble()
        val cutoutH     = (rect.bottom - rect.top).toDouble()
        val cutoutTop   = rect.top.toDouble()   // ← physical px from screen top
        val aspectRatio = if (cutoutH > 0) cutoutW / cutoutH else 0.0
        val type        = if (aspectRatio < 2.0) "punch_hole" else "notch"

        Log.d(TAG, "rect=$rect centerX=$centerX cutoutW=$cutoutW cutoutH=$cutoutH " +
                   "cutoutTop=$cutoutTop aspectRatio=$aspectRatio type=$type")

        return mapOf(
            "type"      to type,
            "centerX"   to centerX,
            "screenW"   to screenW,
            "cutoutH"   to cutoutH,
            "cutoutTop" to cutoutTop   // ← NEW: Dart needs this to position pill
        )
    }

    // ── MIUI punch-hole fallback ───────────────────────────────────────────
    // On MIUI, displayCutout is often null from a plugin context because the
    // window hasn't laid out yet. We use SystemProperties + a dedicated MIUI
    // resource to get the ACTUAL camera circle dimensions, not the full
    // status-bar height (which was the old bug).
    private fun getMiuiCutoutRect(activity: android.app.Activity, screenW: Double): Map<String, Any> {
        return try {
            val sysPropClass = Class.forName("android.os.SystemProperties")
            val getProp      = sysPropClass.getMethod("get", String::class.java, String::class.java)
            val hasMiuiNotch = getProp.invoke(null, "ro.miui.notch", "0") as String
            Log.d(TAG, "ro.miui.notch = '$hasMiuiNotch'")

            if (hasMiuiNotch != "1") {
                return mapOf("type" to "none", "centerX" to 0.0, "screenW" to screenW,
                             "cutoutH" to 0.0, "cutoutTop" to 0.0)
            }

            val res = activity.resources

            // MIUI exposes the camera hole HEIGHT via this private resource.
            // It is the actual circle diameter, NOT the status bar height.
            var cameraH = 0.0
            val camHId = res.getIdentifier("miui_camera_cutout_height", "dimen", "android")
            if (camHId > 0) {
                cameraH = res.getDimensionPixelSize(camHId).toDouble()
                Log.d(TAG, "miui_camera_cutout_height px = $cameraH")
            }

            // MIUI also exposes the camera hole WIDTH
            var cameraW = cameraH   // default: assume circle
            val camWId = res.getIdentifier("miui_camera_cutout_width", "dimen", "android")
            if (camWId > 0) {
                cameraW = res.getDimensionPixelSize(camWId).toDouble()
                Log.d(TAG, "miui_camera_cutout_width px = $cameraW")
            }

            // Status bar height tells us where the top of the cutout sits.
            // On MIUI punch-hole devices the hole is INSIDE the status bar.
            val sbId = res.getIdentifier("status_bar_height", "dimen", "android")
            val sbH  = if (sbId > 0) res.getDimensionPixelSize(sbId).toDouble() else 80.0
            Log.d(TAG, "status_bar_height px = $sbH")

            if (cameraH <= 0.0) {
                // Last resort: guess camera hole is roughly 55-60% of status bar height
                // centered vertically within it. Better than using full sbH as cutoutH.
                cameraH = sbH * 0.58
                Log.d(TAG, "cameraH fallback guess = $cameraH")
            }

            // Camera hole is vertically centered inside the status bar
            val cutoutTop = (sbH - cameraH) / 2.0

            Log.d(TAG, "MIUI final: cutoutTop=$cutoutTop cameraH=$cameraH cameraW=$cameraW screenW=$screenW")

            mapOf(
                "type"      to "punch_hole",
                "centerX"   to screenW / 2.0,
                "screenW"   to screenW,
                "cutoutH"   to cameraH,
                "cutoutTop" to cutoutTop
            )
        } catch (e: Exception) {
            Log.e(TAG, "getMiuiCutoutRect exception: $e")
            mapOf("type" to "none", "centerX" to 0.0, "screenW" to screenW,
                  "cutoutH" to 0.0, "cutoutTop" to 0.0)
        }
    }
}