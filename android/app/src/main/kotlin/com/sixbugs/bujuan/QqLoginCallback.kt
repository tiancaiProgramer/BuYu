// Community maintenance and new features: tiancaiProgramer.
package com.sixbugs.bujuan

import java.net.URI
import java.net.URLDecoder

/** A one-use official music authorization callback, never a password or cookie bridge. */
data class QqLoginCallback(val code: String, val loginType: Int) {
    companion object {
        fun parse(url: String): QqLoginCallback? = try {
            val uri = URI(url)
            if (uri.scheme != "https" || uri.host != "y.qq.com" || uri.rawUserInfo != null ||
                (uri.port != -1 && uri.port != 443) || uri.rawPath != "/portal/wx_redirect.html") null
            else {
                val pairs = (uri.rawQuery ?: "").split('&').map {
                    val p = it.split('=', limit = 2)
                    URLDecoder.decode(p[0], "UTF-8") to URLDecoder.decode(p.getOrElse(1) { "" }, "UTF-8")
                }
                val values = pairs.toMap()
                val code = values["code"] ?: ""
                val type = when (values["login_type"]) { "1" -> 2; "2" -> 1; else -> 0 }
                if (pairs.map { it.first }.distinct().size != pairs.size || type == 0 ||
                    code.isBlank() || code.length > 4096 || code.any { it.code < 32 }) null
                else QqLoginCallback(code, type)
            }
        } catch (_: Exception) { null }
    }
}
