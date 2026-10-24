package com.huanming.glean

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Leaving from the home tabs sends the app to the background instead
        // of finishing the activity, so coming back skips the splash and
        // lands where the user was.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "glean/app")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "moveTaskToBack" -> result.success(moveTaskToBack(true))
                    else -> result.notImplemented()
                }
            }
    }
}
