package com.numelixa.tapcode

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.AnimatorSet
import android.animation.ObjectAnimator
import android.app.Service
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.IBinder
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast

/** User-authorized compact liquid-glass OTP card. No access to or automation of other apps. */
class TapCodeOverlayService : Service() {
    private var windowManager: WindowManager? = null
    private var card: View? = null
    private var params: WindowManager.LayoutParams? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_DISMISS) { dismissAnimated(); return START_NOT_STICKY }
        if (Build.VERSION.SDK_INT < 23 || !android.provider.Settings.canDrawOverlays(this)) {
            stopSelf(); return START_NOT_STICKY
        }
        val orderId = intent?.getStringExtra(EXTRA_ORDER_ID).orEmpty()
        val entry = TapCodeVault.read(this).firstOrNull { it.orderId == orderId }
        if (entry == null || !TapCodeVault.isEnabled(this) ||
            !getSharedPreferences(PREFS, 0).getBoolean(KEY_OVERLAY_ENABLED, false)) {
            stopSelf(); return START_NOT_STICKY
        }
        showCard(entry)
        return START_NOT_STICKY
    }

    private fun showCard(entry: TapCodeEntry) {
        removeCard()
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager

        // A translucent glass surface with a subtle violet-to-cyan edge.
        val shell = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(1), dp(1), dp(1), dp(1))
            background = GradientDrawable(
                GradientDrawable.Orientation.LEFT_RIGHT,
                intArrayOf(Color.rgb(125, 75, 255), Color.rgb(0, 218, 225), Color.rgb(61, 134, 255))
            ).apply { cornerRadius = dp(25).toFloat() }
            elevation = dp(18).toFloat()
        }
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(17), dp(14), dp(17), dp(15))
            background = GradientDrawable(
                GradientDrawable.Orientation.TL_BR,
                intArrayOf(Color.argb(247, 10, 19, 39), Color.argb(239, 7, 24, 42), Color.argb(247, 12, 15, 34))
            ).apply {
                cornerRadius = dp(24).toFloat()
                setStroke(dp(1), Color.argb(105, 173, 224, 255))
            }
        }
        shell.addView(root, LinearLayout.LayoutParams(-1, -2))

        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val logo = ImageView(this).apply {
            scaleType = ImageView.ScaleType.FIT_CENTER
            val bitmap = try {
                assets.open("flutter_assets/assets/numelixa_app_icon.webp").use {
                    BitmapFactory.decodeStream(it)
                }
            } catch (_: Exception) { null }
            if (bitmap != null) setImageBitmap(bitmap)
            contentDescription = "Numelixa"
        }
        header.addView(logo, LinearLayout.LayoutParams(dp(43), dp(43)).apply { marginEnd = dp(11) })
        val titleGroup = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        val title = TextView(this).apply {
            text = "OTP detected"
            setTextColor(Color.WHITE); textSize = 16f
            setTypeface(Typeface.DEFAULT, Typeface.BOLD)
        }
        val subtitle = TextView(this).apply {
            text = "NUMELIXA  ·  SECURE CODE"
            setTextColor(Color.rgb(111, 205, 220)); textSize = 9.5f
            letterSpacing = .12f
        }
        titleGroup.addView(title); titleGroup.addView(subtitle)
        header.addView(titleGroup, LinearLayout.LayoutParams(0, -2, 1f))
        val close = TextView(this).apply {
            text = "×"; textSize = 26f; setTextColor(Color.rgb(194, 210, 229))
            gravity = Gravity.CENTER; contentDescription = "Dismiss OTP popup"
            setOnClickListener { dismissAnimated() }
        }
        header.addView(close, LinearLayout.LayoutParams(dp(35), dp(40)))
        root.addView(header)

        val serviceTitle = TextView(this).apply {
            text = entry.service + " verification code"
            setTextColor(Color.rgb(191, 207, 227)); textSize = 13f
            setPadding(dp(2), dp(15), 0, dp(5))
        }
        root.addView(serviceTitle)
        val codePanel = LinearLayout(this).apply {
            gravity = Gravity.CENTER
            setPadding(dp(12), dp(9), dp(12), dp(9))
            background = GradientDrawable().apply {
                setColor(Color.argb(115, 28, 50, 78))
                cornerRadius = dp(15).toFloat()
                setStroke(dp(1), Color.argb(75, 89, 178, 220))
            }
        }
        val code = TextView(this).apply {
            text = entry.code; textSize = 29f; letterSpacing = .24f
            setTextColor(Color.WHITE); setTypeface(Typeface.DEFAULT, Typeface.BOLD)
        }
        codePanel.addView(code)
        root.addView(codePanel, LinearLayout.LayoutParams(-1, dp(59)))

        val expiry = TextView(this).apply {
            val seconds = ((entry.expiresAt - System.currentTimeMillis()).coerceAtLeast(0L) / 1000L)
            text = "Available for " + seconds + " sec  ·  " + entry.phone
            setTextColor(Color.rgb(130, 157, 185)); textSize = 10.5f
            setPadding(dp(2), dp(7), 0, dp(12))
        }
        root.addView(expiry)

        val actions = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val autofill = actionButton("Autofill", intArrayOf(Color.rgb(110, 38, 221), Color.rgb(0, 139, 220)), true)
        autofill.setOnClickListener {
            copyCode(entry.code)
            Toast.makeText(this@TapCodeOverlayService,
                "Code copied. Select the OTP field and paste, or use Android Autofill if offered.",
                Toast.LENGTH_LONG).show()
            dismissAnimated()
        }
        val copy = actionButton("Copy", intArrayOf(Color.rgb(14, 39, 60), Color.rgb(10, 31, 51)), false)
        copy.setOnClickListener {
            copyCode(entry.code)
            Toast.makeText(this@TapCodeOverlayService, "OTP copied", Toast.LENGTH_SHORT).show()
            dismissAnimated()
        }
        actions.addView(autofill, LinearLayout.LayoutParams(0, dp(45), 1f).apply { marginEnd = dp(7) })
        actions.addView(copy, LinearLayout.LayoutParams(0, dp(45), 1f).apply { marginStart = dp(7) })
        root.addView(actions)

        @Suppress("DEPRECATION")
        val type = if (Build.VERSION.SDK_INT >= 26) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else WindowManager.LayoutParams.TYPE_PHONE
        val layout = WindowManager.LayoutParams(
            (resources.displayMetrics.widthPixels - dp(30)).coerceAtMost(dp(370)),
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                (if (Build.VERSION.SDK_INT >= 31) WindowManager.LayoutParams.FLAG_BLUR_BEHIND else 0),
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            y = dp(78)
            if (Build.VERSION.SDK_INT >= 31) {
                @Suppress("NewApi")
                blurBehindRadius = dp(18)
            }
        }

        // Drag only from the header so the action buttons remain fully clickable.
        header.setOnTouchListener(object : View.OnTouchListener {
            private var downX = 0f; private var downY = 0f
            private var startX = 0; private var startY = 0
            override fun onTouch(v: View, event: MotionEvent): Boolean {
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        downX = event.rawX; downY = event.rawY
                        startX = layout.x; startY = layout.y
                        return true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        layout.x = startX + (event.rawX - downX).toInt()
                        layout.y = startY + (event.rawY - downY).toInt()
                        try { windowManager?.updateViewLayout(shell, layout) } catch (_: Exception) {}
                        return true
                    }
                    MotionEvent.ACTION_UP -> return true
                }
                return false
            }
        })
        try {
            windowManager?.addView(shell, layout)
            card = shell; params = layout
            shell.alpha = 0f; shell.scaleX = .94f; shell.scaleY = .94f
            AnimatorSet().apply {
                playTogether(
                    ObjectAnimator.ofFloat(shell, View.ALPHA, 0f, 1f),
                    ObjectAnimator.ofFloat(shell, View.SCALE_X, .94f, 1f),
                    ObjectAnimator.ofFloat(shell, View.SCALE_Y, .94f, 1f)
                )
                duration = 260L
                start()
            }
        } catch (_: Exception) { stopSelf() }
    }

    private fun actionButton(label: String, colors: IntArray, primary: Boolean): Button =
        Button(this).apply {
            text = label
            isAllCaps = false
            textSize = 13f
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            background = GradientDrawable(
                GradientDrawable.Orientation.LEFT_RIGHT, colors
            ).apply {
                cornerRadius = dp(23).toFloat()
                if (!primary) setStroke(dp(1), Color.rgb(0, 184, 211))
            }
            stateListAnimator = null
            elevation = 0f
            minHeight = 0; minimumHeight = 0
            setPadding(dp(8), 0, dp(8), 0)
        }

    private fun copyCode(value: String) {
        (getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager)
            .setPrimaryClip(ClipData.newPlainText("Numelixa verification code", value))
    }

    private fun dismissAnimated() {
        val view = card ?: run { stopSelf(); return }
        view.animate().alpha(0f).scaleX(.96f).scaleY(.96f).setDuration(170L)
            .withEndAction { removeCard(); stopSelf() }.start()
    }

    private fun removeCard() {
        val view = card ?: return
        try { windowManager?.removeView(view) } catch (_: Exception) {}
        card = null; params = null
    }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
    override fun onDestroy() { removeCard(); super.onDestroy() }

    companion object {
        const val ACTION_SHOW = "com.numelixa.tapcode.SHOW"
        const val ACTION_DISMISS = "com.numelixa.tapcode.DISMISS"
        const val EXTRA_ORDER_ID = "orderId"
        const val PREFS = "numelixa_tapcode_vault"
        const val KEY_OVERLAY_ENABLED = "overlay_enabled"
        fun show(context: Context, orderId: String) {
            val intent = Intent(context, TapCodeOverlayService::class.java)
                .setAction(ACTION_SHOW).putExtra(EXTRA_ORDER_ID, orderId)
            try { context.startService(intent) } catch (_: Exception) { /* Use notification/Autofill fallback. */ }
        }
    }
}
