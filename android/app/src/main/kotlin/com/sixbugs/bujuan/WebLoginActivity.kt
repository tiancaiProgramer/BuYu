// Community maintenance and new features: tiancaiProgramer.
package com.sixbugs.bujuan

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.net.Uri
import android.net.http.SslError
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.webkit.*
import android.view.View
import android.widget.*
import java.io.ByteArrayInputStream
import java.net.URL
import javax.net.ssl.HttpsURLConnection

/** Credentials and security verification belong entirely to the official HTTPS page. */
class WebLoginActivity : Activity() {
    private lateinit var web: WebView
    private lateinit var status: TextView
    private lateinit var progress: ProgressBar
    private val handler = Handler(Looper.getMainLooper())
    @Volatile private var completed = false
    private var ready = false
    private var sdkUserAgent = ""
    private var sdkSource: ByteArray? = null
    private val sdkLock = Any()
    // The official CtWebLogin component reads loginType from the top-level query.
    // Open its phone verification mode directly, avoiding the QR-to-phone initialization path.
    private val loginUrl = "https://music.163.com/?loginType=captchaLogin#/login"
    private val poll = object : Runnable {
        override fun run() {
            if (!completed && ready) checkLogin(false)
            if (!completed) handler.postDelayed(this, 1000)
        }
    }

    private fun allows(url: String): Boolean {
        val uri = Uri.parse(url)
        val host = uri.host?.lowercase() ?: return false
        return uri.scheme == "https" && (uri.port == -1 || uri.port == 443) &&
            uri.userInfo == null && (host == "music.163.com" || host.endsWith(".music.163.com") ||
            host == "reg.163.com" || host == "dl.reg.163.com" || host == "id.163.com")
    }

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.WHITE)
            fitsSystemWindows = true
        }
        val toolbar = LinearLayout(this)
        toolbar.addView(Button(this).apply {
            text = "关闭"
            setOnClickListener { finish() }
        })
        toolbar.addView(TextView(this).apply {
            text = "网易云官方登录 · music.163.com"
            setTextColor(Color.BLACK)
            textSize = 16f
        }, LinearLayout.LayoutParams(0, -2, 1f))
        toolbar.addView(Button(this).apply {
            text = "重新加载"
            setOnClickListener { web.loadUrl(loginUrl) }
        })
        root.addView(toolbar)
        progress = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal)
        root.addView(progress, LinearLayout.LayoutParams(-1, dp(3)))
        status = TextView(this).apply {
            setTextColor(Color.rgb(50, 50, 50))
            setPadding(dp(12), dp(8), dp(12), dp(8))
            text = "请在网易云官方网页完成手机号登录和安全验证，成功后会自动返回 BuYu。"
        }
        root.addView(status)
        web = WebView(this)
        root.addView(web, LinearLayout.LayoutParams(-1, 0, 1f))
        root.addView(Button(this).apply {
            text = "完成认证，返回 BuYu"
            isAllCaps = false
            setOnClickListener { checkLogin(true) }
        }, LinearLayout.LayoutParams(-1, -2))
        setContentView(root)
        web.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            allowFileAccess = false
            allowContentAccess = false
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            javaScriptCanOpenWindowsAutomatically = false
            setSupportMultipleWindows(false)
            useWideViewPort = true
            loadWithOverviewMode = true
            builtInZoomControls = true
            displayZoomControls = false
            // The desktop official page includes phone authentication on tablets and phones.
            val chrome = Regex("Chrome/[0-9.]+").find(userAgentString)?.value ?: "Chrome/120.0.0.0"
            userAgentString = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) $chrome Safari/537.36"
        }
        sdkUserAgent = web.settings.userAgentString
        val cookies = CookieManager.getInstance()
        cookies.setAcceptCookie(true)
        cookies.setAcceptThirdPartyCookies(web, true)
        web.webViewClient = object : WebViewClient() {
            override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
                // The official login component itself lists these public SDK mirrors.
                // Bound its initial download so a stalled CDN cannot leave the phone dialog spinning forever.
                if (request.method == "GET" && request.url.toString() ==
                    "https://urswebzj.nosdn.127.net/webzj_cdn101/message.js") return loadOfficialSdk()
                return null
            }
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                if (!request.isForMainFrame) return false
                if (allows(request.url.toString())) return false
                status.text = "请使用此页的网页登录；该链接无法在认证页内打开。"
                return true
            }
            @Deprecated("Legacy Android callback")
            override fun shouldOverrideUrlLoading(view: WebView, url: String) = !allows(url)
            override fun onPageStarted(view: WebView, url: String, favicon: Bitmap?) {
                if (!allows(url)) {
                    view.stopLoading()
                    status.text = "已停止打开非官方认证页面，请重新加载。"
                }
            }
            override fun onPageFinished(view: WebView, url: String) {
                if (allows(url)) {
                    preparePage()
                    checkLogin(false)
                }
            }
            override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                if (request.isForMainFrame) status.text = "登录页加载失败，请检查网络后重新加载。"
            }
            override fun onReceivedHttpError(view: WebView, request: WebResourceRequest, response: WebResourceResponse) {
                if (request.isForMainFrame) status.text = "官方登录服务暂不可用，请稍后重新加载。"
            }
            override fun onReceivedSslError(view: WebView, sslHandler: SslErrorHandler, error: SslError) {
                sslHandler.cancel()
                status.text = "连接证书验证失败，请检查设备时间和网络。"
            }
        }
        web.webChromeClient = object : WebChromeClient() {
            override fun onProgressChanged(view: WebView, value: Int) {
                progress.progress = value
                progress.visibility = if (value == 100) View.GONE else View.VISIBLE
            }
        }
        // Clear only this app's separate WebView session. The music API's current session is untouched.
        cookies.removeAllCookies {
            if (!isFinishing && !isDestroyed) {
                WebStorage.getInstance().deleteAllData()
                ready = true
                web.loadUrl(loginUrl)
                handler.postDelayed(poll, 1000)
            }
        }
    }

    private fun preparePage() {
        if (Uri.parse(web.url ?: "").host != "music.163.com") return
        // Presentation and resource hints only; no form access, credential bridge or verification automation.
        web.evaluateJavascript("""
            (() => {
              if (document.getElementById('buyu-auth-layout')) return;
              const style = document.createElement('style');
              style.id = 'buyu-auth-layout';
              style.textContent = '.g-btmbar,.g-ft,#g_backtop{display:none!important}';
              document.head.appendChild(style);
              for (const host of ['https://dl.reg.163.com','https://urswebzj.nosdn.127.net']) {
                const link = document.createElement('link'); link.rel = 'preconnect'; link.href = host;
                document.head.appendChild(link);
              }
              const preload = document.createElement('link'); preload.rel = 'preload'; preload.as = 'script';
              preload.href = 'https://urswebzj.nosdn.127.net/webzj_cdn101/message.js';
              document.head.appendChild(preload);
            })()
        """.trimIndent(), null)
    }

    private fun loadOfficialSdk(): WebResourceResponse = synchronized(sdkLock) {
        if (sdkSource == null) {
            val urls = listOf(
                "https://urswebzj.nosdn.127.net/webzj_cdn101/message.js",
                "https://webzj.netstatic.net/webzj_cdn101/message4.js",
                "https://dl.reg.163.com/webzj/ngx/message.js"
            )
            for (address in urls) {
                if (completed) break
                var connection: HttpsURLConnection? = null
                try {
                    connection = URL(address).openConnection() as HttpsURLConnection
                    connection.connectTimeout = 4000
                    connection.readTimeout = 4000
                    connection.instanceFollowRedirects = false
                    connection.setRequestProperty("User-Agent", sdkUserAgent)
                    connection.setRequestProperty("Accept-Encoding", "identity")
                    if (connection.responseCode != 200) continue
                    val bytes = connection.inputStream.use { it.readBytesLimited(512 * 1024) }
                    if (bytes.isNotEmpty()) { sdkSource = bytes; break }
                } catch (_: Exception) {
                    // No URL query, cookies or authentication data are logged.
                } finally {
                    connection?.disconnect()
                }
            }
        }
        val bytes = sdkSource
        if (bytes == null) {
            handler.post {
                if (!completed) status.text = "官方手机号认证组件加载失败，请检查网络后重新加载，或返回使用二维码登录。"
            }
            WebResourceResponse("application/javascript", "UTF-8", 503, "Unavailable",
                mapOf("Cache-Control" to "no-store"), ByteArrayInputStream(ByteArray(0)))
        } else {
            WebResourceResponse("application/javascript", "UTF-8", ByteArrayInputStream(bytes))
        }
    }

    private fun java.io.InputStream.readBytesLimited(limit: Int): ByteArray {
        val buffer = java.io.ByteArrayOutputStream()
        val chunk = ByteArray(8192)
        while (true) {
            val count = read(chunk)
            if (count < 0) break
            if (buffer.size() + count > limit) throw java.io.IOException("SDK response too large")
            buffer.write(chunk, 0, count)
        }
        return buffer.toByteArray()
    }

    private fun checkLogin(reportMissing: Boolean) {
        if (completed || !ready || !allows(web.url ?: "")) return
        val cookies = CookieManager.getInstance()
        val header = cookies.getCookie("https://music.163.com/") ?: ""
        val hasSession = header.split(';').any {
            it.trim().startsWith("MUSIC_U=") && it.trim().substringAfter('=').isNotBlank()
        }
        if (!hasSession) {
            if (reportMissing) status.text = "尚未取得登录状态，请在官方网页完成登录和安全验证。"
            return
        }
        completed = true
        cookies.flush()
        setResult(RESULT_OK, Intent().putExtra("cookies", header))
        finish()
    }

    @Deprecated("Activity back compatibility")
    override fun onBackPressed() {
        if (web.canGoBack()) web.goBack() else super.onBackPressed()
    }

    override fun onDestroy() {
        completed = true
        handler.removeCallbacksAndMessages(null)
        if (::web.isInitialized) {
            web.stopLoading()
            web.webChromeClient = null
            web.webViewClient = WebViewClient()
            web.destroy()
        }
        super.onDestroy()
    }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
}
