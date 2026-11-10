// Community maintenance and new features: tiancaiProgramer.
import com.sixbugs.bujuan.QqLoginCallback

/** Standalone JVM regression; no Android framework or real account required. */
fun main() {
    val base = "https://y.qq.com/portal/wx_redirect.html"
    check(QqLoginCallback.parse("$base?login_type=1&code=qq-fixture") == QqLoginCallback("qq-fixture", 2))
    check(QqLoginCallback.parse("$base?login_type=2&code=wx%2Bfixture&surl=https%3A%2F%2Fy.qq.com%2F") == QqLoginCallback("wx+fixture", 1))
    val invalid = listOf(
        "http://y.qq.com/portal/wx_redirect.html?login_type=1&code=fixture",
        "https://y.qq.com.evil.example/portal/wx_redirect.html?login_type=1&code=fixture",
        "https://y.qq.com@evil.example/portal/wx_redirect.html?login_type=1&code=fixture",
        "https://evil.example@y.qq.com/portal/wx_redirect.html?login_type=1&code=fixture",
        "https://y.qq.com:444/portal/wx_redirect.html?login_type=1&code=fixture",
        "https://u.y.qq.com/portal/wx_redirect.html?login_type=1&code=fixture",
        "$base?login_type=1&code=fixture&code=other",
        "$base?login_type=0&code=fixture",
        "$base?login_type=1&code=",
        "$base?login_type=1&code=%0Afixture",
        "$base?login_type=1&code=%ZZ",
        "$base?login_type=1#code=fixture",
    )
    for (url in invalid) check(QqLoginCallback.parse(url) == null)
    println("14 official callback checks passed")
}
