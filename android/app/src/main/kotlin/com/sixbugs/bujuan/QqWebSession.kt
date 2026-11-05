// Community maintenance and new features: tiancaiProgramer.
package com.sixbugs.bujuan

import android.webkit.CookieManager

/** Only completed QQ Music cookies cross the private platform channel. Never log values. */
object QqWebSession {
    private val cookieNames = setOf("uin", "wxuin", "qqmusic_uin", "qqmusic_key", "qm_keyst", "login_type", "tmeLoginType")
    private val renewalNames = setOf("openid", "unionid", "access_token", "refresh_token", "refresh_key", "expired_in")
    val names get() = cookieNames + renewalNames
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
        val renewal = values.filterKeys { it in renewalNames }
        if (renewal.isEmpty()) return cookies
        return org.json.JSONObject().put("cookies", cookies).put("refresh", org.json.JSONObject(renewal)).toString()
    }
}
