package com.numelixa.tapcode

import android.app.Service
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
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
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast

/** Small user-authorized OTP overlay. It never reads or controls another app's UI. */
class TapCodeOverlayService : Service() {
    private var windowManager: WindowManager? = null
    private var card: View? = null
    private var params: WindowManager.LayoutParams? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_DISMISS) { removeCard(); stopSelf(); return START_NOT_STICKY }
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
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(13), dp(16), dp(14))
            background = GradientDrawable(
                GradientDrawable.Orientation.TL_BR,
                intArrayOf(Color.rgb(18, 23, 43), Color.rgb(5, 16, 31))
            ).apply {
                cornerRadius = dp(20).toFloat()
                setStroke(dp(2), Color.rgb(0, 205, 220))
            }
            elevation = dp(12).toFloat()
        }
        val header = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        val brand = TextView(this).apply {
            text = "N  NUMELIXA"
            setTextColor(Color.rgb(0, 218, 235)); textSize = 15f
            setTypeface(typeface, Typeface.BOLD)
        }
        val close = TextView(this).apply {
            text = "×"; textSize = 26f; setTextColor(Color.LTGRAY); gravity = Gravity.CENTER
            setOnClickListener { removeCard(); stopSelf() }
        }
        header.addView(brand, LinearLayout.LayoutParams(0, dp(34), 1f))
        header.addView(close, LinearLayout.LayoutParams(dp(36), dp(34)))
        root.addView(header)
        val detected = TextView(this).apply {
            text = "OTP DETECTED  ·  " + entry.service
            setTextColor(Color.LTGRAY); textSize = 12f
            setPadding(0, dp(8), 0, dp(5))
        }
        root.addView(detected)
        val code = TextView(this).apply {
            text = entry.code; textSize = 27f; letterSpacing = .18f
            setTextColor(Color.WHITE); setTypeface(typeface, Typeface.BOLD)
            setPadding(0, dp(3), 0, dp(10))
        }
        root.addView(code)
        val actions = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        val autofill = Button(this).apply {
            text = "⚡ Autofill"; isAllCaps = false
            setOnClickListener {
                copyCode(entry.code)
                Toast.makeText(this@TapCodeOverlayService,
                    "Code copied. Android Autofill can fill it when the active app supports Autofill.",
                    Toast.LENGTH_LONG).show()
                removeCard(); stopSelf()
            }
        }
        val copy = Button(this).apply {
            text = "Copy"; isAllCaps = false
            setOnClickListener {
                copyCode(entry.code)
                Toast.makeText(this@TapCodeOverlayService, "OTP copied", Toast.LENGTH_SHORT).show()
                removeCard(); stopSelf()
            }
        }
        actions.addView(autofill, LinearLayout.LayoutParams(0, dp(46), 1f))
        actions.addView(copy, LinearLayout.LayoutParams(0, dp(46), 1f))
        root.addView(actions)

        @Suppress("DEPRECATION")
        val type = if (Build.VERSION.SDK_INT >= 26) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else WindowManager.LayoutParams.TYPE_PHONE
        val layout = WindowManager.LayoutParams(
            min(resources.displayMetrics.widthPixels - dp(32), dp(360)),
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply { gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL; y = dp(90) }
        root.setOnTouchListener(object : View.OnTouchListener {
            private var downX = 0f; private var downY = 0f; private var startX = 0; private var startY = 0
            override fun onTouch(v: View, event: MotionEvent): Boolean {
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> { downX=event.rawX; downY=event.rawY; startX=layout.x; startY=layout.y; return true }
                    MotionEvent.ACTION_MOVE -> { layout.x=startX+(event.rawX-downX).toInt(); layout.y=startY+(event.rawY-downY).toInt(); windowManager?.updateViewLayout(root,layout); return true }
                    MotionEvent.ACTION_UP -> return true
                }; return false
            }
        })
        try { windowManager?.addView(root, layout); card = root; params = layout }
        catch (_: Exception) { stopSelf() }
    }

    private fun copyCode(value: String) {
        (getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager)
            .setPrimaryClip(ClipData.newPlainText("Numelixa verification code", value))
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
            try {
                context.startService(intent)
            } catch (_: Exception) { /* Notification/Autofill remains the fallback. */ }
        }
    }
}
