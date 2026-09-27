package com.adaptive.physicalcomm.adaptive_physical_communication

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Window-level brightness needs no WRITE_SETTINGS permission and is
        // dropped by the system as soon as the activity goes away.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "apcs/optical_display")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setMaxBrightness" -> {
                        setWindowBrightness(WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_FULL)
                        result.success(null)
                    }
                    "restoreBrightness" -> {
                        setWindowBrightness(WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun setWindowBrightness(value: Float) {
        runOnUiThread {
            val attrs = window.attributes
            attrs.screenBrightness = value
            window.attributes = attrs
        }
    }
}
