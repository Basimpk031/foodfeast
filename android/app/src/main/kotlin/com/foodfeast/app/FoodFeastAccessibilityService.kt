package com.foodfeast.app

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.graphics.*
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.*
import android.view.accessibility.AccessibilityEvent
import android.widget.*

class FoodFeastAccessibilityService : AccessibilityService() {

    companion object {
        @Volatile var instance: FoodFeastAccessibilityService? = null
    }

    private val handler = Handler(Looper.getMainLooper())
    private var windowManager: WindowManager? = null
    private var overlayView: FrameLayout? = null
    private var overlayParams: WindowManager.LayoutParams? = null
    private var isExpanded = false
    private var collapseRunnable: Runnable? = null
    private var currentOrderId = ""

    private val d get() = resources.displayMetrics.density
    private val COLL_W get() = (126 * d).toInt()
    private val COLL_H get() = (34  * d).toInt()
    private val EXP_W  get() = (300 * d).toInt()
    private val EXP_H  get() = (124 * d).toInt()
    private val CORNER get() = 20f * d

    // ── Transparent Padding for Expanding Collapsed Touch Area ──────
    private val PADDING_X get() = (20 * d).toInt()
    private val PADDING_Y get() = (20 * d).toInt()

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance      = this
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager

        serviceInfo = serviceInfo?.also { info ->
            info.eventTypes    = 0
            info.feedbackType  = AccessibilityServiceInfo.FEEDBACK_GENERIC
            info.flags         = AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
            info.notificationTimeout = 0
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}
    override fun onInterrupt() {}

    override fun onDestroy() {
        instance = null
        removeOverlay()
        super.onDestroy()
    }

    fun showOrUpdate(orderId: String, status: String) {
        handler.post {
            currentOrderId = orderId
            removeOverlay()
            isExpanded = false
            buildAndAddWindow(orderId, status)
        }
    }

    fun dismiss() {
        handler.post {
            collapseRunnable?.let { handler.removeCallbacks(it) }
            removeOverlay()
        }
    }

    private fun buildAndAddWindow(orderId: String, status: String) {
        val container = FrameLayout(this)

        val collapsed = buildCollapsed(status).also {
            it.tag = "collapsed"
            it.background = GradientDrawable().apply {
                shape        = GradientDrawable.RECTANGLE
                cornerRadius = CORNER
                setColor(Color.BLACK)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                it.elevation = 0f
            }
        }
        val expanded  = buildExpanded(orderId, status).also {
            it.tag        = "expanded"
            it.visibility = View.GONE
            it.alpha      = 0f
            it.background = GradientDrawable().apply {
                shape        = GradientDrawable.RECTANGLE
                cornerRadius = CORNER
                setColor(Color.BLACK)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                it.elevation = 999f
            }
        }

        container.addView(collapsed, FrameLayout.LayoutParams(COLL_W, COLL_H, Gravity.CENTER))
        container.addView(expanded,  FrameLayout.LayoutParams(EXP_W,  EXP_H, Gravity.CENTER))

        val params = WindowManager.LayoutParams(
            COLL_W + 2 * PADDING_X, COLL_H + 2 * PADDING_Y,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE            or
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL          or
            WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH      or
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN         or
            WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x       = getCameraScreenCenterX() - COLL_W / 2 - PADDING_X
            y       = calculateTargetY() - PADDING_Y

        }

        // ── Native Click Handling (Fixed) ──
        container.setOnTouchListener { _, event ->
            if (event.action == MotionEvent.ACTION_OUTSIDE) {
                if (isExpanded) collapse()
                return@setOnTouchListener true
            }
            false 
        }

        container.setOnClickListener {
            if (isExpanded) collapse() else expand(orderId)
        }

        container.setOnLongClickListener {
            if (isExpanded) collapse() else expand(orderId)
            true
        }

        overlayView   = container
        overlayParams = params
        windowManager?.addView(container, params)
    }

    private fun expand(orderId: String) {
        val container = overlayView ?: return
        val params    = overlayParams ?: return
        isExpanded    = true

        params.y      = calculateTargetY()
        params.x      = getCameraScreenCenterX() - EXP_W / 2
        params.width  = EXP_W
        params.height = EXP_H
        try { windowManager?.updateViewLayout(container, params) } catch (_: Exception) {}

        val lp = container.layoutParams?.also { it.width = EXP_W; it.height = EXP_H }
        if (lp != null) container.layoutParams = lp
        container.requestLayout()

        val collapsed = container.findViewWithTag<View>("collapsed")
        val expanded  = container.findViewWithTag<View>("expanded")

        collapsed?.animate()?.alpha(0f)?.setDuration(120)?.withEndAction {
            handler.post {
                collapsed.visibility = View.GONE
                expanded?.visibility = View.VISIBLE
                expanded?.animate()?.alpha(1f)?.setDuration(200)?.start()
            }
        }?.start()

        collapseRunnable?.let { handler.removeCallbacks(it) }
        collapseRunnable = Runnable { if (isExpanded) collapse() }
        handler.postDelayed(collapseRunnable!!, 6000)
    }

    private fun collapse() {
        val container = overlayView ?: return
        val params    = overlayParams ?: return
        isExpanded    = false
        collapseRunnable?.let { handler.removeCallbacks(it) }

        val collapsed = container.findViewWithTag<View>("collapsed")
        val expanded  = container.findViewWithTag<View>("expanded")

        expanded?.animate()?.alpha(0f)?.setDuration(120)?.withEndAction {
            handler.post {
                expanded.visibility  = View.GONE
                collapsed?.visibility = View.VISIBLE
                collapsed?.animate()?.alpha(1f)?.setDuration(200)?.start()

                val lp = container.layoutParams?.also {
                    it.width = COLL_W + 2 * PADDING_X
                    it.height = COLL_H + 2 * PADDING_Y
                }
                if (lp != null) container.layoutParams = lp
                container.requestLayout()

                params.width  = COLL_W + 2 * PADDING_X
                params.height = COLL_H + 2 * PADDING_Y
                params.x      = getCameraScreenCenterX() - COLL_W / 2 - PADDING_X
                params.y      = calculateTargetY() - PADDING_Y
                try { windowManager?.updateViewLayout(container, params) } catch (_: Exception) {}
            }
        }?.start()
    }

    private fun removeOverlay() {
        collapseRunnable?.let { handler.removeCallbacks(it) }
        overlayView?.let {
            try { windowManager?.removeView(it) } catch (_: Exception) {}
        }
        overlayView     = null
        overlayParams   = null
    }

    private fun calculateTargetY(): Int {
        val minGap = (8 * d).toInt()
        val cutout = getCutoutInfo()
        val targetY: Int

        if (cutout != null && cutout.height > 0) {
            var holeCenterY = cutout.top + (cutout.height / 2)
            if (cutout.top <= 0) holeCenterY = getStatusBarHeight() / 2
            targetY = holeCenterY - (COLL_H / 2)
        } else {
            targetY = (getStatusBarHeight() - COLL_H) / 2
        }
        return targetY.coerceAtLeast(minGap)
    }

    // ── Screen Measurement Fixes ──────────────────────────────────────────
    private fun getScreenWidthPx(): Int {
        return android.content.res.Resources.getSystem().displayMetrics.widthPixels
    }

    private fun getCameraScreenCenterX(): Int {
        val screenW = getScreenWidthPx()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                val wm = getSystemService(WINDOW_SERVICE) as WindowManager
                val rects = wm.maximumWindowMetrics.windowInsets.displayCutout?.boundingRects
                if (!rects.isNullOrEmpty()) {
                    val top = rects.minByOrNull { it.top }
                    if (top != null) return (top.left + top.right) / 2
                }
            } catch (_: Exception) {}
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                val wm = getSystemService(WINDOW_SERVICE) as WindowManager
                @Suppress("DEPRECATION")
                val rects = wm.defaultDisplay.cutout?.boundingRects
                if (!rects.isNullOrEmpty()) {
                    val top = rects.minByOrNull { it.top }
                    if (top != null) return (top.left + top.right) / 2
                }
            } catch (_: Exception) {}
        }
        return screenW / 2
    }

    private data class CutoutRect(val top: Int, val height: Int)

    private fun getCutoutInfo(): CutoutRect? {
        val maxHolePx = (50 * d).toInt()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            return try {
                val wm = getSystemService(WINDOW_SERVICE) as WindowManager
                val cutouts = wm.maximumWindowMetrics.windowInsets.displayCutout?.boundingRects
                if (cutouts.isNullOrEmpty()) return oemFallback(maxHolePx)
                val top = cutouts.minByOrNull { it.top } ?: return oemFallback(maxHolePx)
                val h = top.height().coerceAtMost(maxHolePx)
                if (h <= 0) return oemFallback(maxHolePx)
                CutoutRect(top = top.top, height = h)
            } catch (_: Exception) { oemFallback(maxHolePx) }
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return try {
                val wm = getSystemService(WINDOW_SERVICE) as WindowManager
                @Suppress("DEPRECATION")
                val cutouts = wm.defaultDisplay.cutout?.boundingRects
                if (cutouts.isNullOrEmpty()) return oemFallback(maxHolePx)
                val top = cutouts.minByOrNull { it.top } ?: return oemFallback(maxHolePx)
                val h = top.height().coerceAtMost(maxHolePx)
                if (h <= 0) return oemFallback(maxHolePx)
                CutoutRect(top = top.top, height = h)
            } catch (_: Exception) { oemFallback(maxHolePx) }
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            return oemFallback(maxHolePx)
        }
        return null
    }

    private fun oemFallback(maxHolePx: Int): CutoutRect? {
        val res = resources
        try {
            val withCutoutId = res.getIdentifier("status_bar_height_with_cutout", "dimen", "android")
            val normalId     = res.getIdentifier("status_bar_height", "dimen", "android")
            if (withCutoutId > 0 && normalId > 0) {
                val holeH = (res.getDimensionPixelSize(withCutoutId) - res.getDimensionPixelSize(normalId))
                    .coerceAtMost(maxHolePx)
                if (holeH > 0) {
                    val sbH = res.getDimensionPixelSize(normalId)
                    return CutoutRect(top = ((sbH - holeH) / 2).coerceAtLeast(0), height = holeH)
                }
            }
        } catch (_: Exception) {}
        try {
            val camHId = res.getIdentifier("miui_camera_cutout_height", "dimen", "android")
            if (camHId > 0) {
                val cameraH = res.getDimensionPixelSize(camHId).coerceAtMost(maxHolePx)
                if (cameraH > 0) {
                    val sbId = res.getIdentifier("status_bar_height", "dimen", "android")
                    val sbH  = if (sbId > 0) res.getDimensionPixelSize(sbId) else (28 * d).toInt()
                    return CutoutRect(top = ((sbH - cameraH) / 2).coerceAtLeast(0), height = cameraH)
                }
            }
        } catch (_: Exception) {}
        val sbH   = getStatusBarHeight()
        val holeH = (sbH * 0.60).toInt().coerceAtMost(maxHolePx)
        return CutoutRect(top = (sbH - holeH) / 2, height = holeH)
    }

    private fun getStatusBarHeight(): Int {
        return try {
            val id = resources.getIdentifier("status_bar_height", "dimen", "android")
            if (id > 0) resources.getDimensionPixelSize(id) else (28 * d).toInt()
        } catch (_: Exception) { (28 * d).toInt() }
    }

    private fun buildCollapsed(status: String): RelativeLayout {
        val meta = statusMeta(status)
        return RelativeLayout(this).apply {
            val emojiView = TextView(context).apply {
                id = View.generateViewId(); text = meta.emoji; textSize = 16f
                paintFlags = paintFlags or Paint.SUBPIXEL_TEXT_FLAG
            }
            addView(emojiView, RelativeLayout.LayoutParams(
                RelativeLayout.LayoutParams.WRAP_CONTENT,
                RelativeLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                addRule(RelativeLayout.ALIGN_PARENT_START)
                addRule(RelativeLayout.CENTER_VERTICAL)
                marginStart = (10 * d).toInt()
            })
            addView(View(context).apply {
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL; setColor(Color.parseColor("#F97316"))
                }
            }, RelativeLayout.LayoutParams((7 * d).toInt(), (7 * d).toInt()).apply {
                addRule(RelativeLayout.ALIGN_PARENT_END)
                addRule(RelativeLayout.CENTER_VERTICAL)
                marginEnd = (10 * d).toInt()
            })
        }
    }

    private fun buildExpanded(orderId: String, status: String): LinearLayout {
        val meta    = statusMetaFull(status)
        val accent  = Color.parseColor(meta.color)
        val shortId = if (orderId.length >= 8) orderId.take(8).uppercase() else orderId.uppercase()

        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity     = Gravity.CENTER_VERTICAL
            setPadding((14*d).toInt(), (12*d).toInt(), (14*d).toInt(), (12*d).toInt())

            addView(LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)

                addView(FrameLayout(context).apply {
                    val s = (36*d).toInt()
                    layoutParams = LinearLayout.LayoutParams(s, s).also { it.marginEnd = (10*d).toInt() }
                    background = GradientDrawable().apply {
                        shape = GradientDrawable.RECTANGLE; cornerRadius = 10*d
                        setColor(Color.argb(46, Color.red(accent), Color.green(accent), Color.blue(accent)))
                        setStroke((1*d).toInt(), Color.argb(90, Color.red(accent), Color.green(accent), Color.blue(accent)))
                    }
                    addView(TextView(context).apply {
                        text = meta.emoji; textSize = 17f; gravity = Gravity.CENTER
                        layoutParams = FrameLayout.LayoutParams(
                            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT)
                    })
                })

                addView(LinearLayout(context).apply {
                    orientation = LinearLayout.VERTICAL
                    layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
                    addView(TextView(context).apply {
                        text = meta.label; textSize = 14f; setTextColor(Color.WHITE)
                        typeface = android.graphics.Typeface.create(android.graphics.Typeface.DEFAULT, android.graphics.Typeface.BOLD)
                    })
                    addView(TextView(context).apply {
                        text = meta.sub; textSize = 10.5f
                        setTextColor(Color.argb(140, 255, 255, 255))
                        layoutParams = LinearLayout.LayoutParams(
                            LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT
                        ).also { it.topMargin = (2*d).toInt() }
                    })
                })

                addView(TextView(context).apply {
                    text = "✕"; textSize = 11f; setTextColor(Color.argb(130, 255, 255, 255))
                    gravity = Gravity.CENTER
                    val s = (26*d).toInt()
                    layoutParams = LinearLayout.LayoutParams(s, s)
                    background = GradientDrawable().apply {
                        shape = GradientDrawable.OVAL; setColor(Color.argb(25, 255, 255, 255))
                    }
                    setOnClickListener { collapse() }
                })
            })

            addView(View(context).apply {
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT, (1*d).toInt()
                ).also { it.topMargin = (10*d).toInt(); it.bottomMargin = (10*d).toInt() }
                setBackgroundColor(Color.argb(20, 255, 255, 255))
            })

            addView(LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)

                addView(TextView(context).apply {
                    text = "#$shortId"; textSize = 9.5f
                    setTextColor(Color.argb(128, 255, 255, 255))
                    typeface = android.graphics.Typeface.MONOSPACE
                    layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
                    setPadding((8*d).toInt(), (4*d).toInt(), (8*d).toInt(), (4*d).toInt())
                    background = GradientDrawable().apply {
                        shape = GradientDrawable.RECTANGLE; cornerRadius = 8*d
                        setColor(Color.argb(18, 255, 255, 255))
                        setStroke((1*d).toInt(), Color.argb(30, 255, 255, 255))
                    }
                })

                addView(TextView(context).apply {
                    text = "▶  Track"; textSize = 11f; setTextColor(Color.WHITE)
                    typeface = android.graphics.Typeface.create(android.graphics.Typeface.DEFAULT, android.graphics.Typeface.BOLD)
                    gravity = Gravity.CENTER
                    layoutParams = LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT
                    ).also { it.marginStart = (8*d).toInt() }
                    setPadding((14*d).toInt(), (8*d).toInt(), (14*d).toInt(), (8*d).toInt())
                    background = GradientDrawable().apply {
                        shape = GradientDrawable.RECTANGLE; cornerRadius = 20*d; setColor(accent)
                    }
                    setOnClickListener { openApp(orderId) }
                })
            })
        }
    }

    private fun openApp(orderId: String) {
        packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = android.content.Intent.FLAG_ACTIVITY_NEW_TASK or
                    android.content.Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("open_tracking", true)
            putExtra(DynamicIslandOverlayService.EXTRA_ORDER_ID, orderId)
        }?.let { startActivity(it) }
    }

    private data class S3(val emoji: String, val label: String, val color: String)
    private data class S4(val emoji: String, val label: String, val sub: String, val color: String)

    private fun statusMeta(s: String) = when (s) {
        "confirmed"        -> S3("✅","Confirmed",  "#0EA5E9")
        "preparing"        -> S3("👨‍🍳","Preparing",  "#F97316")
        "ready_for_pickup" -> S3("🛵","Ready!",     "#F97316")
        "picked_up"        -> S3("📦","Picked Up",  "#0EA5E9")
        "out_for_delivery" -> S3("🚀","On the Way", "#0EA5E9")
        "delivered"        -> S3("🎉","Delivered!", "#22C55E")
        "cancelled"        -> S3("❌","Cancelled",  "#EF4444")
        else               -> S3("🕐","Placed",     "#F97316")
    }

    private fun statusMetaFull(s: String) = when (s) {
        "confirmed"        -> S4("✅","Confirmed",  "Order accepted",        "#0EA5E9")
        "preparing"        -> S4("👨‍🍳","Preparing",  "Kitchen is cooking",    "#F97316")
        "ready_for_pickup" -> S4("🛵","Ready!",     "Finding agent",         "#F97316")
        "picked_up"        -> S4("📦","Picked Up",  "Agent has your order",  "#0EA5E9")
        "out_for_delivery" -> S4("🚀","On the Way", "Heading to you!",       "#0EA5E9")
        "delivered"        -> S4("🎉","Delivered!", "Enjoy your meal 😋",    "#22C55E")
        "cancelled"        -> S4("❌","Cancelled",  "Order was cancelled",   "#EF4444")
        else               -> S4("🕐","Placed",     "Waiting for restaurant","#F97316")
    }
}