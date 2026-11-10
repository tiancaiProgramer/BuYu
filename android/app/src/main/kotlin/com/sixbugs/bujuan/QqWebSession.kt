// Community maintenance and new features: tiancaiProgramer.
package com.sixbugs.bujuan

import android.webkit.CookieManager

/** Only completed QQ Music cookies cross the private platform channel. Never log values. */
object QqWebSession {
    private val cookieNames = setOf("uin", "wxuin", "qqmusic_uin", "qqmusic_key", "qm_keyst", "login_type", "tmeLoginType")
    private val renewalNames = setOf("openid", "unionid", "access_token", "refresh_token", "refresh_key", "expired_in", "wxopenid", "wxunionid", "wxrefresh_token")
    val names get() = cookieNames + renewalNames
    /** Keep browser fallback from offering an older key after app-side renewal. */
    fun update(session: String) {
        val header = if (session.trimStart().startsWith("{")) org.json.JSONObject(session).getString("cookies") else session
        val values = header.split(';').mapNotNull {
            val name = it.substringBefore('=').trim()
            val value = it.substringAfter('=', "").trim()
            if (name in cookieNames && value.isNotEmpty() && !value.any { ch -> ch == '\r' || ch == '\n' || ch == ';' }) name to value else null
        }.toMap()
        val manager = CookieManager.getInstance()
        for (url in listOf("https://y.qq.com/", "https://u.y.qq.com/")) {
            for ((name, value) in values) {
                for (domain in listOf("", "; Domain=.y.qq.com", "; Domain=.qq.com", "; Domain=${android.net.Uri.parse(url).host}")) {
                    manager.setCookie(url, "$name=$value; Path=/$domain; Secure")
                }
            }
        }
        manager.flush()
    }
    fun clear(done: () -> Unit) {
        val manager = CookieManager.getInstance()
        val targets = listOf("https://y.qq.com/", "https://u.y.qq.com/")
        val expired = targets.flatMap { url -> names.flatMap { name ->
            listOf("", "; Domain=.y.qq.com", "; Domain=.qq.com", "; Domain=${android.net.Uri.parse(url).host}").map { domain ->
                url to "$name=; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Path=/$domain"
            }
        } }
        var remaining = expired.size
        for ((url, cookie) in expired) manager.setCookie(url, cookie) {
            remaining--
            if (remaining == 0) { manager.flush(); done() }
        }
    }
    fun read(): String? {
        val values = linkedMapOf<String, String>()
        val manager = CookieManager.getInstance()
        for (url in listOf("https://y.qq.com/", "https://u.y.qq.com/")) {
            for (part in (manager.getCookie(url) ?: "").split(';')) {
                val name = part.substringBefore('=').trim()
                val value = part.substringAfter('=', "").trim()
                if (name in (names + renewalNames) && value.isNotBlank() && !value.contains('\r') && !value.contains('\n')) values[name] = value
            }
        }
        if ((values["qqmusic_uin"] ?: values["uin"] ?: values["wxuin"]).isNullOrBlank() ||
            (values["qqmusic_key"] ?: values["qm_keyst"]).isNullOrBlank()) return null
        val cookies = values.filterKeys { it in cookieNames }.entries.joinToString("; ") { "${it.key}=${it.value}" }
        val renewal = values.filterKeys { it in renewalNames }.toMutableMap()
        for (name in listOf("openid", "unionid", "refresh_token")) {
            if (renewal[name].isNullOrBlank()) renewal["wx$name"]?.let { renewal[name] = it }
            renewal.remove("wx$name")
        }
        if (renewal.isEmpty()) return cookies
        val refresh = org.json.JSONObject()
        for ((name, value) in renewal) refresh.put(name, value)
        return org.json.JSONObject().put("cookies", cookies).put("refresh", refresh).toString()
    }
}
