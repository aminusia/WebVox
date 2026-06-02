package app.alkyo.webreader

import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray

class MainActivity : AudioServiceActivity() {
    private val channelName = "app.alkyo.webreader/system"
    private val mainHandler = Handler(Looper.getMainLooper())
    private val desktopUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
            "AppleWebKit/537.36 (KHTML, like Gecko) " +
            "Chrome/148.0.0.0 Safari/537.36"
    private val baseRenderHeaders = mapOf(
        "rsc" to "1",
        "sec-ch-ua" to "\"Chromium\";v=\"148\", \"Google Chrome\";v=\"148\", \"Not/A)Brand\";v=\"99\"",
        "sec-ch-ua-mobile" to "?0",
        "sec-ch-ua-platform" to "\"macOS\"",
        "sec-fetch-dest" to "empty",
        "sec-fetch-mode" to "cors",
        "sec-fetch-site" to "same-origin"
    )

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
                    "renderUrlToHtml" -> {
                        val url = call.argument<String>("url")
                        val refererUrl = call.argument<String>("refererUrl")
                        val timeoutMillis =
                            (call.argument<Int>("timeoutMillis") ?: 15000).coerceIn(3000, 30000)
                        if (url.isNullOrBlank()) {
                            result.error("INVALID_URL", "URL is required", null)
                        } else {
                            renderUrlToHtml(url, refererUrl, timeoutMillis.toLong(), result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun renderUrlToHtml(
        url: String,
        refererUrl: String?,
        timeoutMillis: Long,
        result: MethodChannel.Result
    ) {
        mainHandler.post {
            var completed = false
            var webView: WebView? = null

            fun finish(html: String?) {
                if (completed) return
                completed = true
                result.success(html)
                webView?.stopLoading()
                webView?.destroy()
                webView = null
            }

            fun evaluateHtml() {
                val view = webView ?: return finish(null)
                view.evaluateJavascript(
                    """
                    (() => {
                      const article = document.querySelector(
                        'article, main, [itemprop="articleBody"], .chapter-content, .chapter-body, .article-content, .entry-content'
                      );
                      const text = (article || document.body)?.innerText || '';
                      
                      // Enhance buttons with data-href if they have onclick handlers
                      document.querySelectorAll('button[aria-label][onclick]').forEach(btn => {
                        if (!btn.hasAttribute('data-href')) {
                          const href = btn.getAttribute('data-href') || btn.getAttribute('href');
                          if (!href) {
                            // Try to infer href from nearby link or data attributes
                            const parent = btn.closest('a[href]');
                            if (parent) {
                              btn.setAttribute('data-href', parent.getAttribute('href'));
                            }
                          }
                        }
                      });

                      // Inject the live (hydrated) document.title into a meta tag so the
                      // Dart parser can read it even when og:title is an SSR placeholder.
                      const existingMeta = document.querySelector('meta[name="x-hydrated-title"]');
                      if (!existingMeta && document.title) {
                        const meta = document.createElement('meta');
                        meta.setAttribute('name', 'x-hydrated-title');
                        meta.setAttribute('content', document.title);
                        document.head.appendChild(meta);
                      }
                      
                      return {
                        ready: text.trim().length > 500,
                        html: document.documentElement.outerHTML
                      };
                    })()
                    """.trimIndent()
                ) { value ->
                    val json = decodeJsString(value)
                    if (json == null) {
                        finish(null)
                        return@evaluateJavascript
                    }

                    val ready = json.contains("\"ready\":true")
                    val htmlMarker = "\"html\":\""
                    val html = if (ready && json.contains(htmlMarker)) {
                        try {
                            org.json.JSONObject(json).optString("html", null)
                        } catch (_: Exception) {
                            null
                        }
                    } else {
                        null
                    }
                    finish(html)
                }
            }

            try {
                webView = WebView(this).apply {
                    settings.javaScriptEnabled = true
                    settings.domStorageEnabled = true
                    settings.cacheMode = WebSettings.LOAD_DEFAULT
                    settings.userAgentString = desktopUserAgent
                    webViewClient = object : WebViewClient() {
                        override fun onPageFinished(view: WebView?, url: String?) {
                            mainHandler.postDelayed({ evaluateHtml() }, 3500)
                        }

                        override fun shouldOverrideUrlLoading(
                            view: WebView?,
                            request: WebResourceRequest?
                        ): Boolean = false
                    }
                }

                mainHandler.postDelayed({ finish(null) }, timeoutMillis)
                val headers = baseRenderHeaders.toMutableMap()
                if (!refererUrl.isNullOrBlank()) {
                    headers["Referer"] = refererUrl.trim()
                }
                webView?.loadUrl(url, headers)
            } catch (e: Exception) {
                finish(null)
            }
        }
    }

    private fun decodeJsString(value: String?): String? {
        if (value == null || value == "null") return null
        if (value.startsWith("{") || value.startsWith("[")) return value
        return try {
            JSONArray("[$value]").getString(0)
        } catch (_: Exception) {
            null
        }
    }
}
