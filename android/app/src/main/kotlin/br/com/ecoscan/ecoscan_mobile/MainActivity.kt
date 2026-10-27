package br.com.ecoscan.ecoscan_mobile

import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "br.com.ecoscan/app_exit",
        ).setMethodCallHandler { call, result ->
            if (call.method != "finishTask") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            result.success(null)
            runOnUiThread {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    finishAndRemoveTask()
                } else {
                    finish()
                }
            }
        }
    }
}
