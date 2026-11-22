package com.numelixa.tapcode

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

class TapCodePlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    private lateinit var appContext: Context
    private lateinit var channel: MethodChannel
    private var activity: Activity? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "com.numelixa.app/tapcode")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getStatus" -> {
                val service = if (Build.VERSION.SDK_INT >= 26) appContext.getSystemService("autofill") else null
                val osEnabled = if (Build.VERSION.SDK_INT >= 26 && service != null) {
                    try {
                        service.javaClass.getMethod("hasEnabledAutofillServices").invoke(service) as? Boolean == true &&
                            Settings.Secure.getString(appContext.contentResolver, "autofill_service")
                                .orEmpty().contains("TapCodeAutofillService")
                    } catch (_: Exception) { false }
                } else false
                result.success(mapOf(
                    "available" to (Build.VERSION.SDK_INT >= 26),
                    "enabled" to TapCodeVault.isEnabled(appContext),
                    "osEnabled" to osEnabled,
                    "hasCodes" to TapCodeVault.read(appContext).isNotEmpty(),
                    "overlayAvailable" to (Build.VERSION.SDK_INT >= 23),
                    "overlayPermission" to (Build.VERSION.SDK_INT >= 23 && Settings.canDrawOverlays(appContext)),
                    "overlayEnabled" to appContext.getSharedPreferences(TapCodeOverlayService.PREFS, 0).getBoolean(TapCodeOverlayService.KEY_OVERLAY_ENABLED, false)
                ))
            }
            "enableTapCode", "openAutofillSettings" -> {
                if (Build.VERSION.SDK_INT < 26) {
                    result.error("UNSUPPORTED", "Android Autofill requires Android 8.0 or newer.", null)
                } else {
                    TapCodeVault.setEnabled(appContext, true)
                    val current = activity
                    if (current == null) {
                        result.error("NO_ACTIVITY", "Open TapCode settings from Numelixa to configure Android Autofill.", null)
                    } else {
                        current.startActivity(Intent(
                            "android.settings.REQUEST_SET_AUTOFILL_SERVICE",
                            Uri.parse("package:" + appContext.packageName)
                        ))
                        result.success(null)
                    }
                }
            }
            "requestOverlayPermission" -> {
                if (Build.VERSION.SDK_INT < 23) {
                    result.error("UNSUPPORTED", "Floating windows require Android 6.0 or newer.", null)
                } else if (Settings.canDrawOverlays(appContext)) {
                    appContext.getSharedPreferences(TapCodeOverlayService.PREFS, 0).edit().putBoolean(TapCodeOverlayService.KEY_OVERLAY_ENABLED, true).apply()
                    result.success(true)
                } else {
                    val current = activity
                    if (current == null) result.error("NO_ACTIVITY", "Open Numelixa settings to grant floating-window permission.", null)
                    else {
                        current.startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:" + appContext.packageName)))
                        result.success(false)
                    }
                }
            }
            "setOverlayEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") == true
                appContext.getSharedPreferences(TapCodeOverlayService.PREFS, 0).edit().putBoolean(TapCodeOverlayService.KEY_OVERLAY_ENABLED, enabled).apply()
                if (!enabled) appContext.stopService(Intent(appContext, TapCodeOverlayService::class.java))
                result.success(null)
            }
            "dismissOverlay" -> {
                appContext.stopService(Intent(appContext, TapCodeOverlayService::class.java))
                result.success(null)
            }
            "disableTapCode" -> {
                TapCodeVault.setEnabled(appContext, false)
                result.success(null)
            }
            "syncOrders" -> {
                @Suppress("UNCHECKED_CAST")
                val orders = call.argument<List<Map<String, Any?>>>("orders") ?: emptyList()
                @Suppress("UNCHECKED_CAST")
                val activeOrders = call.argument<List<Map<String, Any?>>>("activeOrders") ?: emptyList()
                TapCodeVault.putOrders(appContext, orders, activeOrders)
                result.success(null)
            }
            "cachePushOtp" -> {
                val orderId = call.argument<String>("orderId").orEmpty()
                TapCodeVault.updateExistingOrder(appContext, orderId, call.argument<String>("code").orEmpty())
                val overlayPrefs = appContext.getSharedPreferences(TapCodeOverlayService.PREFS, 0)
                if (overlayPrefs.getBoolean(TapCodeOverlayService.KEY_OVERLAY_ENABLED, false) &&
                    Build.VERSION.SDK_INT >= 23 && Settings.canDrawOverlays(appContext) &&
                    TapCodeVault.read(appContext).any { it.orderId == orderId }) {
                    TapCodeOverlayService.show(appContext, orderId)
                }
                result.success(null)
            }
            "clearOrder" -> {
                TapCodeVault.clearOrder(appContext, call.argument<String>("orderId").orEmpty())
                result.success(null)
            }
            "clearAll" -> {
                TapCodeVault.clear(appContext)
                result.success(null)
            }
            "createAdminTestCode" -> {
                val code = call.argument<String>("code").orEmpty()
                if (!TapCodeVault.isEnabled(appContext)) {
                    result.error("TAPCODE_DISABLED", "Enable TapCode before running the Autofill test.", null)
                } else if (!code.matches(Regex("^\\d{6}$"))) {
                    result.error("INVALID_TEST_CODE", "The test code must contain six digits.", null)
                } else {
                    TapCodeVault.putAdminTestCode(appContext, code)
                    val overlayPrefs = appContext.getSharedPreferences(TapCodeOverlayService.PREFS, 0)
                    if (overlayPrefs.getBoolean(TapCodeOverlayService.KEY_OVERLAY_ENABLED, false) &&
                        Build.VERSION.SDK_INT >= 23 && Settings.canDrawOverlays(appContext)) {
                        TapCodeOverlayService.show(appContext, TapCodeVault.ADMIN_TEST_ORDER_ID)
                    }
                    result.success(null)
                }
            }
            "clearAdminTestCode" -> {
                TapCodeVault.clearAdminTestCode(appContext)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivityForConfigChanges() { activity = null }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivity() { activity = null }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        activity = null
    }
}

internal data class TapCodeEntry(
    val orderId: String,
    val code: String,
    val service: String,
    val phone: String,
    val expiresAt: Long
)

internal data class TapCodeActiveOrder(
    val orderId: String,
    val service: String,
    val phone: String,
    val expiresAt: Long
)

internal object TapCodeVault {
    private const val PREFS = "numelixa_tapcode_vault"
    private const val ALIAS = "numelixa_tapcode_aes_v1"
    const val ADMIN_TEST_ORDER_ID = "__numelixa_admin_tapcode_test__"

    fun setEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS, 0).edit().putBoolean("enabled", enabled).apply()
        if (!enabled) clear(context)
    }

    fun isEnabled(context: Context): Boolean =
        context.getSharedPreferences(PREFS, 0).getBoolean("enabled", false)

    fun putOrders(
        context: Context,
        orders: List<Map<String, Any?>>,
        activeOrders: List<Map<String, Any?>>
    ) {
        if (!isEnabled(context)) { clear(context); return }
        val now = System.currentTimeMillis()
        val active = LinkedHashMap<String, TapCodeActiveOrder>()
        activeOrders.take(100).forEach { item ->
            val id = item["orderId"]?.toString()?.trim().orEmpty()
            val expiry = (item["expiresAt"] as? Number)?.toLong() ?: 0L
            if (id.isNotEmpty() && expiry > now) {
                active[id] = TapCodeActiveOrder(
                    id,
                    item["service"]?.toString()?.take(50) ?: "Virtual number",
                    item["phone"]?.toString()?.take(32) ?: "",
                    expiry
                )
            }
        }

        val existingTestOrder = readActiveOrders(context).firstOrNull {
            it.orderId == ADMIN_TEST_ORDER_ID && it.expiresAt > now
        }
        if (existingTestOrder != null) active[ADMIN_TEST_ORDER_ID] = existingTestOrder
        val suppressed = readSuppressedOrderIds(context).filter { it in active }
        val merged = LinkedHashMap<String, TapCodeEntry>()
        read(context).filter { it.orderId in active && it.orderId !in suppressed && it.expiresAt > now }
            .forEach { merged[it.orderId] = it }
        orders.take(10).forEach { item ->
            val id = item["orderId"]?.toString()?.trim().orEmpty()
            val code = item["code"]?.toString()?.trim().orEmpty()
            val expiry = (item["expiresAt"] as? Number)?.toLong() ?: 0L
            val metadata = active[id]
            if (metadata != null && id !in suppressed && code.matches(Regex("^\\d{4,8}$")) && expiry > now) {
                merged[id] = TapCodeEntry(id, code, metadata.service, metadata.phone,
                    minOf(expiry, metadata.expiresAt))
            }
        }
        writePayload(context, merged.values.take(10).toList(), active.values.toList(), suppressed)
    }

    fun putAdminTestCode(context: Context, code: String) {
        if (!isEnabled(context) || !code.matches(Regex("^\\d{6}$"))) return
        val now = System.currentTimeMillis()
        val expiry = now + 3 * 60 * 1000L
        val entries = read(context).filterNot { it.orderId == ADMIN_TEST_ORDER_ID }.toMutableList()
        val active = readActiveOrders(context).filterNot { it.orderId == ADMIN_TEST_ORDER_ID }.toMutableList()
        active.add(TapCodeActiveOrder(ADMIN_TEST_ORDER_ID, "Admin Autofill test", "This device", expiry))
        entries.add(TapCodeEntry(ADMIN_TEST_ORDER_ID, code, "Admin Autofill test", "This device", expiry))
        writePayload(context, entries.take(10), active, readSuppressedOrderIds(context).filterNot { it == ADMIN_TEST_ORDER_ID })
    }

    fun clearAdminTestCode(context: Context) {
        val entries = read(context).filterNot { it.orderId == ADMIN_TEST_ORDER_ID }
        val active = readActiveOrders(context).filterNot { it.orderId == ADMIN_TEST_ORDER_ID }
        writePayload(context, entries, active, readSuppressedOrderIds(context).filterNot { it == ADMIN_TEST_ORDER_ID })
    }

    fun updateExistingOrder(context: Context, orderId: String, code: String) {
        if (!isEnabled(context) || orderId.isBlank() || !code.matches(Regex("^\\d{4,8}$"))) return
        if (orderId in readSuppressedOrderIds(context)) return
        val active = readActiveOrders(context).firstOrNull { it.orderId == orderId } ?: return
        val now = System.currentTimeMillis()
        if (active.expiresAt <= now) return
        val expiry = minOf(active.expiresAt, now + 10 * 60 * 1000L)
        val entries = read(context).filterNot { it.orderId == orderId }.toMutableList()
        entries.add(TapCodeEntry(orderId, code, active.service, active.phone, expiry))
        writePayload(context, entries.take(10), readActiveOrders(context), readSuppressedOrderIds(context))
    }

    fun clearOrder(context: Context, orderId: String) {
        val entries = read(context).filterNot { it.orderId == orderId }
        val active = readActiveOrders(context)
        val activeIds = active.map { it.orderId }.toSet()
        val suppressed = (readSuppressedOrderIds(context) + orderId).distinct().filter { it in activeIds }
        writePayload(context, entries, active, suppressed)
    }

    fun clear(context: Context) {
        context.getSharedPreferences(PREFS, 0).edit().remove("payload").apply()
    }

    fun read(context: Context): List<TapCodeEntry> {
        val payload = readPayload(context) ?: return emptyList()
        val list = payload.optJSONArray("entries") ?: JSONArray()
        val now = System.currentTimeMillis()
        val entries = mutableListOf<TapCodeEntry>()
        for (i in 0 until list.length()) {
            val item = list.optJSONObject(i) ?: continue
            val code = item.optString("code")
            val expiry = item.optLong("expiresAt")
            val id = item.optString("orderId")
            if (id.isNotBlank() && code.matches(Regex("^\\d{4,8}$")) && expiry > now) {
                entries.add(TapCodeEntry(id, code, item.optString("service"),
                    item.optString("phone"), expiry))
            }
        }
        val active = readActiveOrders(context)
        val suppressed = readSuppressedOrderIds(context).filter { id -> active.any { it.orderId == id } }
        val visibleEntries = entries.filterNot { it.orderId in suppressed }
        val rawActiveCount = payload.optJSONArray("activeOrders")?.length() ?: 0
        val rawSuppressedCount = payload.optJSONArray("suppressedOrderIds")?.length() ?: 0
        if (visibleEntries.size != list.length() || active.size != rawActiveCount ||
            suppressed.size != rawSuppressedCount) {
            writePayload(context, visibleEntries, active, suppressed)
        }
        return visibleEntries
    }

    private fun readActiveOrders(context: Context): List<TapCodeActiveOrder> {
        val list = readPayload(context)?.optJSONArray("activeOrders") ?: return emptyList()
        val now = System.currentTimeMillis()
        val orders = mutableListOf<TapCodeActiveOrder>()
        for (i in 0 until list.length()) {
            val item = list.optJSONObject(i) ?: continue
            val id = item.optString("orderId")
            val expiry = item.optLong("expiresAt")
            if (id.isNotBlank() && expiry > now) {
                orders.add(TapCodeActiveOrder(id, item.optString("service"),
                    item.optString("phone"), expiry))
            }
        }
        return orders
    }

    private fun readSuppressedOrderIds(context: Context): List<String> {
        val payload = readPayload(context) ?: return emptyList()
        val active = payload.optJSONArray("activeOrders") ?: JSONArray()
        val activeIds = mutableSetOf<String>()
        val now = System.currentTimeMillis()
        for (i in 0 until active.length()) {
            val item = active.optJSONObject(i) ?: continue
            val id = item.optString("orderId")
            if (id.isNotBlank() && item.optLong("expiresAt") > now) activeIds.add(id)
        }
        val list = payload.optJSONArray("suppressedOrderIds") ?: JSONArray()
        return (0 until list.length()).mapNotNull { list.optString(it).takeIf { id -> id in activeIds } }.distinct()
    }

    private fun readPayload(context: Context): JSONObject? {
        return try {
            val raw = context.getSharedPreferences(PREFS, 0).getString("payload", null) ?: return null
            val decoded = android.util.Base64.decode(raw, android.util.Base64.DEFAULT)
            if (decoded.size < 13) return null
            val iv = decoded.copyOfRange(0, 12)
            val ciphertext = decoded.copyOfRange(12, decoded.size)
            val cipher = javax.crypto.Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(javax.crypto.Cipher.DECRYPT_MODE, key(), javax.crypto.spec.GCMParameterSpec(128, iv))
            JSONObject(String(cipher.doFinal(ciphertext), Charsets.UTF_8))
        } catch (_: Exception) {
            clear(context)
            null
        }
    }

    private fun writePayload(
        context: Context,
        entries: List<TapCodeEntry>,
        activeOrders: List<TapCodeActiveOrder>,
        suppressedIds: List<String> = emptyList()
    ) {
        val entryJson = JSONArray()
        entries.forEach { entry ->
            entryJson.put(JSONObject().put("orderId", entry.orderId).put("code", entry.code)
                .put("service", entry.service).put("phone", entry.phone).put("expiresAt", entry.expiresAt))
        }
        val activeJson = JSONArray()
        activeOrders.forEach { order ->
            activeJson.put(JSONObject().put("orderId", order.orderId).put("service", order.service)
                .put("phone", order.phone).put("expiresAt", order.expiresAt))
        }
        val suppressedJson = JSONArray()
        suppressedIds.distinct().forEach { suppressedJson.put(it) }
        writeEncrypted(context, JSONObject().put("entries", entryJson)
            .put("activeOrders", activeJson).put("suppressedOrderIds", suppressedJson).toString())
    }

    private fun writeEncrypted(context: Context, value: String) {
        try {
            val cipher = javax.crypto.Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(javax.crypto.Cipher.ENCRYPT_MODE, key())
            val encrypted = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
            val payload = cipher.iv + encrypted
            context.getSharedPreferences(PREFS, 0).edit()
                .putString("payload", android.util.Base64.encodeToString(payload, android.util.Base64.NO_WRAP))
                .apply()
        } catch (_: Exception) { clear(context) }
    }

    private fun key(): java.security.Key {
        val store = java.security.KeyStore.getInstance("AndroidKeyStore")
        store.load(null)
        val existing = store.getKey(ALIAS, null)
        if (existing != null) return existing
        val generator = javax.crypto.KeyGenerator.getInstance(
            android.security.keystore.KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        val spec = android.security.keystore.KeyGenParameterSpec.Builder(
            ALIAS,
            android.security.keystore.KeyProperties.PURPOSE_ENCRYPT or
                android.security.keystore.KeyProperties.PURPOSE_DECRYPT
        ).setBlockModes(android.security.keystore.KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(android.security.keystore.KeyProperties.ENCRYPTION_PADDING_NONE)
            .setRandomizedEncryptionRequired(true)
            .build()
        generator.init(spec)
        return generator.generateKey()
    }
}

class TapCodeAutofillService : android.service.autofill.AutofillService() {
    override fun onFillRequest(
        request: android.service.autofill.FillRequest,
        cancellationSignal: android.os.CancellationSignal,
        callback: android.service.autofill.FillCallback
    ) {
        if (Build.VERSION.SDK_INT < 26 || !TapCodeVault.isEnabled(this)) {
            callback.onSuccess(null)
            return
        }
        val callerPackage = request.fillContexts.lastOrNull()?.structure?.activityComponent?.packageName
        val isNumelixaTestScreen = callerPackage == packageName
        // The synthetic admin test OTP must be offered only to external apps.
        // Never show the test code inside Numelixa itself.
        val entries = TapCodeVault.read(this).filter {
            it.orderId != TapCodeVault.ADMIN_TEST_ORDER_ID || !isNumelixaTestScreen
        }
        if (entries.isEmpty()) { callback.onSuccess(null); return }
        val fields = mutableListOf<Pair<android.view.autofill.AutofillId, Int?>>()
        request.fillContexts.forEach { context -> collectOtpFields(context.structure, fields) }
        if (fields.isEmpty()) { callback.onSuccess(null); return }
        val response = android.service.autofill.FillResponse.Builder()
        var datasetCount = 0
        entries.forEach { entry ->
            val presentation = android.widget.RemoteViews(packageName, android.R.layout.simple_list_item_1)
            val label = listOf("Numelixa", entry.service, entry.phone).filter { it.isNotBlank() }.joinToString(" · ")
            presentation.setTextViewText(android.R.id.text1, label + " — " + entry.code)
            val dataset = android.service.autofill.Dataset.Builder(presentation)
            var hasValue = false
            fields.forEach { field ->
                val value = if (field.second == null) entry.code
                    else entry.code.getOrNull(field.second!! - 1)?.toString() ?: ""
                if (value.isNotEmpty()) {
                    dataset.setValue(field.first, android.view.autofill.AutofillValue.forText(value))
                    hasValue = true
                }
            }
            if (hasValue) {
                response.addDataset(dataset.build())
                datasetCount++
            }
        }
        callback.onSuccess(if (datasetCount > 0) response.build() else null)
    }

    private fun collectOtpFields(
        structure: android.app.assist.AssistStructure,
        output: MutableList<Pair<android.view.autofill.AutofillId, Int?>>
    ) {
        for (i in 0 until structure.windowNodeCount) walk(structure.getWindowNodeAt(i).rootViewNode, output)
    }

    private fun walk(
        node: android.app.assist.AssistStructure.ViewNode,
        output: MutableList<Pair<android.view.autofill.AutofillId, Int?>>
    ) {
        val hints = node.autofillHints?.toSet() ?: emptySet()
        val position = hints.firstNotNullOfOrNull { hint ->
            Regex("^smsOTPCode([1-8])$").matchEntire(hint)?.groupValues?.get(1)?.toInt()
        }
        val explicitOtpHint = hints.any { hint ->
            val value = hint.lowercase()
            value == "smsotpcode" || value.startsWith("smsotpcode") ||
                value == "onetimecode" || value == "one_time_code" ||
                value == "verificationcode" || value == "verification_code" ||
                value == "otp" || value == "otpcode"
        }

        val semanticText = listOfNotNull(
            node.hint?.toString(),
            node.contentDescription?.toString(),
            node.idEntry,
            hints.joinToString(" ")
        ).joinToString(" ").lowercase()
        val otpLabel = Regex(
            """(\botp\b|one[ _-]?time[ _-]?(password|code)|verification[ _-]?(code|token)|authentication[ _-]?code|security[ _-]?code)"""
        ).containsMatchIn(semanticText)
        val excludedLabel = Regex(
            "(phone|mobile|telephone|credit|debit|card|cvv|cvc|postal|zip|address)"
        ).containsMatchIn(semanticText)

        val inputClass = node.inputType and android.text.InputType.TYPE_MASK_CLASS
        val numericInput = inputClass == android.text.InputType.TYPE_CLASS_NUMBER
        val editableText = node.autofillType == android.view.View.AUTOFILL_TYPE_TEXT ||
            node.className?.contains("EditText", ignoreCase = true) == true
        val boundedNumericCode = numericInput && editableText &&
            node.maxTextLength in 4..8 && !excludedLabel

        if ((explicitOtpHint || (otpLabel && !excludedLabel) || boundedNumericCode) &&
            node.autofillId != null) {
            output.add(Pair(node.autofillId!!, position))
        }
        for (i in 0 until node.childCount) walk(node.getChildAt(i), output)
    }

    override fun onSaveRequest(
        request: android.service.autofill.SaveRequest,
        callback: android.service.autofill.SaveCallback
    ) { callback.onSuccess() }
}
