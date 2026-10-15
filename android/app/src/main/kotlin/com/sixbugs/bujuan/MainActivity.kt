package com.sixbugs.bujuan

import android.os.Build
import android.content.Intent
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: AudioServiceActivity() {
    private var audioDownloads: AudioDownloads? = null
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (audioDownloads?.onActivityResult(requestCode, resultCode, data) != true)
            super.onActivityResult(requestCode, resultCode, data)
    }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val downloads = AudioDownloads(this)
        audioDownloads = downloads
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bujuan/downloads")
            .setMethodCallHandler { call, result -> downloads.handle(call, result) }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bujuan/display")
            .setMethodCallHandler { call, result ->
                if (call.method != "getCutoutInsets") {
                    result.notImplemented()
                } else {
                    // Query after the Android view has received its latest window insets.
                    window.decorView.post {
                        val cutout = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
                            window.decorView.rootWindowInsets?.displayCutout else null
                        result.success(mapOf(
                            "left" to (cutout?.safeInsetLeft ?: 0),
                            "top" to (cutout?.safeInsetTop ?: 0),
                            "right" to (cutout?.safeInsetRight ?: 0),
                            "bottom" to (cutout?.safeInsetBottom ?: 0)
                        ))
                    }
                }
            }
    }
}
