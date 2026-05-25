package app.alkyo.webreader

import android.content.Intent
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private val channelName = "app.alkyo.webreader/system"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openTtsSettings" -> {
                        try {
                            val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            // Try TTS-specific settings first, fall back to accessibility
                            val ttsIntent = Intent("com.android.settings.TTS_SETTINGS")
                            ttsIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            val resolveInfo = packageManager.resolveActivity(ttsIntent, 0)
                            if (resolveInfo != null) {
                                startActivity(ttsIntent)
                            } else {
                                startActivity(intent)
                            }
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("UNAVAILABLE", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
