// Community maintenance and new features: tiancaiProgramer.
package com.sixbugs.bujuan

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.net.http.SslError
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.webkit.*
import android.widget.*

/** Official pages own credentials and verification; only the completed music session is returned. */
class QqLoginActivity : Activity() {
    private lateinit var web: WebView
    private lateinit var status: TextView
    private val handler = Handler(Looper.getMainLooper())
    private var completed = false
    private var ready = false
    private val sessionNames = QqWebSession.names
    private val startUrl = "https://y.qq.com/"
    private val poll = object : Runnable {
        override fun run() {
            if (!completed) { check(); handler.postDelayed(this, 1500) }
        }
    }
    private fun official(url: String): Boolean {
        val u = Uri.parse(url); val h = u.host?.lowercase() ?: return false
        return u.scheme == "https" && u.userInfo == null && (u.port == -1 || u.port == 443) &&
            (h == "y.qq.com" || h.endsWith(".y.qq.com") || h == "graph.qq.com" || h == "xui.ptlogin2.qq.com" ||
             h == "ssl.ptlogin2.qq.com" || h == "ptlogin2.qq.com" || h == "ui.ptlogin2.qq.com" ||
             h == "open.weixin.qq.com" || h == "mp.weixin.qq.com" || h == "ssl.captcha.qq.com" || h == "t.captcha.qq.com")
    }
    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(Color.WHITE); fitsSystemWindows = true }
        val toolbar = LinearLayout(this)
        toolbar.addView(Button(this).apply { text = "关闭"; setOnClickListener { finish() } })
        toolbar.addView(TextView(this).apply { text = "QQ音乐官方登录"; setTextColor(Color.BLACK) }, LinearLayout.LayoutParams(0,-2,1f))
        toolbar.addView(Button(this).apply { text = "重新加载"; setOnClickListener { web.loadUrl(startUrl) } })
        root.addView(toolbar)
        status = TextView(this).apply { text = "请点官方页面的登录，完成QQ或微信认证后返回。账号权限与网易云独立。"; setTextColor(Color.DKGRAY); setPadding(16,12,16,12) }
        root.addView(status)
        web = WebView(this); root.addView(web, LinearLayout.LayoutParams(-1,0,1f))
        root.addView(Button(this).apply { text = "完成登录，返回BuYu"; setOnClickListener { check(true) } })
        setContentView(root)
        web.settings.apply {
            javaScriptEnabled = true; domStorageEnabled = true; allowFileAccess = false; allowContentAccess = false
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            javaScriptCanOpenWindowsAutomatically = false; setSupportMultipleWindows(false)
            useWideViewPort = true; loadWithOverviewMode = true; builtInZoomControls = true; displayZoomControls = false
            val chrome = Regex("Chrome/[0-9.]+").find(userAgentString)?.value ?: "Chrome/120.0.0.0"
            userAgentString = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) $chrome Safari/537.36"
        }
        CookieManager.getInstance().apply { setAcceptCookie(true); setAcceptThirdPartyCookies(web,true) }
        web.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, req: WebResourceRequest) = req.isForMainFrame && !official(req.url.toString())
            @Deprecated("Legacy Android callback")
            override fun shouldOverrideUrlLoading(view: WebView, url: String) = !official(url)
            override fun onPageFinished(view: WebView,url: String) { if (official(url)) check() }
            override fun onReceivedSslError(view: WebView,h: SslErrorHandler,error: SslError) {
                h.cancel(); status.text = "官方网页证书验证失败，请检查网络和设备时间。"
            }
            override fun onReceivedError(view: WebView, req: WebResourceRequest, error: WebResourceError) {
                if (req.isForMainFrame) status.text = "官方登录页面加载失败，请检查网络后点重新加载。"
            }
        }
        // Clear only QQ music session cookies, so "switch" cannot immediately return the old login.
        // The separately encrypted app session remains valid until a new account passes validation.
        val manager = CookieManager.getInstance()
        val expired = listOf(startUrl, "https://u.y.qq.com/").flatMap { url -> sessionNames.flatMap { name ->
            listOf("", "; Domain=${Uri.parse(url).host}", "; Domain=.${Uri.parse(url).host}", "; Domain=.y.qq.com", "; Domain=.qq.com").map { domain ->
                url to "$name=; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Path=/$domain"
            }
        } }
        var remaining = expired.size
        for ((url, cookie) in expired) manager.setCookie(url, cookie) {
            remaining--
            if (remaining == 0 && !completed) {
                manager.flush(); ready = true
                web.loadUrl(startUrl); handler.postDelayed(poll,1500)
            }
        }
    }
    private fun check(report: Boolean = false) {
        if (!ready || completed || !official(web.url ?: "")) return
        val header = QqWebSession.read()
        if (header == null) {
            if (report) status.text = "尚未取得QQ音乐登录状态，请先在官方页面完成登录。"
            return
        }
        completed = true; CookieManager.getInstance().flush()
        setResult(RESULT_OK,Intent().putExtra("cookies",header)); finish()
    }
    override fun onDestroy() {
        completed = true; handler.removeCallbacksAndMessages(null)
        if (::web.isInitialized) { web.stopLoading(); web.webViewClient = WebViewClient(); web.destroy() }
        super.onDestroy()
    }
}
