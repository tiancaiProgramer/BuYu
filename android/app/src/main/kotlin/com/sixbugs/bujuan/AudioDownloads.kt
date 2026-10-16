// Community maintenance and new features: tiancaiProgramer.
package com.sixbugs.bujuan

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.widget.Toast
import android.content.ContentValues
import android.content.Intent
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.DocumentsContract
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class AudioDownloads(private val activity: Activity) {
    private var choosing: MethodChannel.Result? = null
    private val directoryRequest = 61243
    fun onActivityResult(request: Int, code: Int, data: Intent?): Boolean {
        if (request != directoryRequest) return false
        val callback = choosing ?: return true
        choosing = null
        val uri = data?.data
        if (code != Activity.RESULT_OK || uri == null) { callback.success(null); return true }
        try {
            val flags = data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            require(flags and Intent.FLAG_GRANT_WRITE_URI_PERMISSION != 0)
            activity.contentResolver.takePersistableUriPermission(uri, flags)
            val name = DocumentsContract.getTreeDocumentId(uri).replace("primary:", "内部存储/")
            callback.success(mapOf("uri" to uri.toString(), "name" to name))
        } catch (error: Exception) { callback.error("DIRECTORY", "无法取得文件夹保存权限", null) }
        return true
    }
    private val notificationStates = mutableMapOf<String, String>()
    private fun downloadStatus(call: MethodCall) {
        val key = call.argument<String>("key") ?: return
        val title = call.argument<String>("title") ?: "音乐下载"
        val state = call.argument<String>("state") ?: return
        val status = call.argument<String>("status") ?: ""
        val active = state == "queued" || state == "downloading" || state == "saving"
        val changed = notificationStates.put(key, state) != state
        if (changed && activity.hasWindowFocus()) {
            if (state == "queued" || state == "complete" || state == "failed")
                Toast.makeText(activity, when (state) {
                    "queued" -> "已加入下载：$title"
                    "complete" -> "下载完成：$title"
                    else -> "$title：$status"
                }, Toast.LENGTH_LONG).show()
        }
        val manager = activity.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val id = 0x40000000 or (key.hashCode() and 0x0fffffff)
        if (state == "cancelled") { manager.cancel(id); return }
        val channel = if (active) "bujuan.download.progress" else "bujuan.download.results"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(NotificationChannel(channel,
                if (active) "下载进度" else "下载结果",
                if (active) NotificationManager.IMPORTANCE_LOW else NotificationManager.IMPORTANCE_DEFAULT).apply {
                    setSound(null, null); enableVibration(false)
                })
        }
        val intent = Intent(activity, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pending = PendingIntent.getActivity(activity, id, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            Notification.Builder(activity, channel) else Notification.Builder(activity)
        builder.setSmallIcon(if (active) android.R.drawable.stat_sys_download else android.R.drawable.stat_sys_download_done)
            .setContentTitle(if (state == "complete") "下载完成 · $title" else title)
            .setContentText(status).setStyle(Notification.BigTextStyle().bigText(status))
            .setContentIntent(pending).setOngoing(active).setAutoCancel(!active)
            .setOnlyAlertOnce(active).setSound(null)
            .setCategory(Notification.CATEGORY_PROGRESS)
        if (active) {
            val total = call.argument<Number>("total")?.toLong() ?: 0L
            val received = call.argument<Number>("received")?.toLong() ?: 0L
            builder.setProgress(100, if (total > 0) ((received.toDouble() / total) * 100).toInt().coerceIn(0, 100) else 0, total <= 0)
        }
        try { manager.notify(id, builder.build()) } catch (_: SecurityException) {
            // App feedback remains available if system notifications are disabled.
        }
    }
    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "downloadStatus") { downloadStatus(call); result.success(null); return }
        if (call.method == "sdk") { result.success(Build.VERSION.SDK_INT); return }
        if (call.method == "chooseDirectory") {
            if (choosing != null) { result.error("BUSY", "文件夹选择器已打开", null); return }
            choosing = result
            try {
                activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
                }, directoryRequest)
            } catch (error: Exception) { choosing = null; result.error("DIRECTORY", "无法打开文件夹选择器", null) }
            return
        }
        if (call.method != "saveAudio") { result.notImplemented(); return }
        Thread {
            try {
                val source = File(requireNotNull(call.argument<String>("source"))).canonicalFile
                require(source.isFile && source.length() > 0)
                require(source.path.startsWith(activity.cacheDir.canonicalPath + File.separator))
                val name = requireNotNull(call.argument<String>("name"))
                require(name.isNotBlank() && File(name).name == name && !name.contains('/'))
                val mime = requireNotNull(call.argument<String>("mime"))
                require(mime == "audio/flac" || mime == "audio/mpeg")
                val uri: Uri
                val tree = call.argument<String>("tree")
                if (!tree.isNullOrEmpty()) {
                    val treeUri = Uri.parse(tree)
                    val document = DocumentsContract.buildDocumentUriUsingTree(treeUri, DocumentsContract.getTreeDocumentId(treeUri))
                    val resolver = activity.contentResolver
                    uri = requireNotNull(DocumentsContract.createDocument(resolver, document, mime, name))
                    try {
                        val count = source.inputStream().use { input ->
                            requireNotNull(resolver.openOutputStream(uri)).use { output -> input.copyTo(output) }
                        }
                        check(count == source.length())
                    } catch (error: Exception) {
                        DocumentsContract.deleteDocument(resolver, uri)
                        throw error
                    }
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    val resolver = activity.contentResolver
                    val values = ContentValues().apply {
                        put(MediaStore.Audio.Media.DISPLAY_NAME, name)
                        put(MediaStore.Audio.Media.MIME_TYPE, mime)
                        put(MediaStore.Audio.Media.TITLE, call.argument<String>("title"))
                        put(MediaStore.Audio.Media.ARTIST, call.argument<String>("artist"))
                        put(MediaStore.Audio.Media.ALBUM, call.argument<String>("album"))
                        put(MediaStore.Audio.Media.IS_MUSIC, 1)
                        put(MediaStore.Audio.Media.RELATIVE_PATH, "${Environment.DIRECTORY_MUSIC}/BuJuan")
                        put(MediaStore.Audio.Media.IS_PENDING, 1)
                    }
                    uri = requireNotNull(resolver.insert(MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY), values))
                    try {
                        val count = source.inputStream().use { input ->
                            requireNotNull(resolver.openOutputStream(uri)).use { output -> input.copyTo(output) }
                        }
                        check(count == source.length())
                        values.clear(); values.put(MediaStore.Audio.Media.IS_PENDING, 0)
                        check(resolver.update(uri, values, null, null) == 1)
                    } catch (error: Exception) {
                        resolver.delete(uri, null, null)
                        throw error
                    }
                } else {
                    @Suppress("DEPRECATION")
                    val directory = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC), "BuJuan")
                    check(directory.isDirectory || directory.mkdirs())
                    var target = File(directory, name)
                    if (target.exists()) target = File(directory, "${System.currentTimeMillis()}_$name")
                    val part = File(directory, ".${target.name}.part")
                    try {
                        source.copyTo(part, overwrite = false)
                        check(part.length() == source.length() && part.renameTo(target))
                    } finally { if (part.exists()) part.delete() }
                    uri = Uri.fromFile(target)
                    MediaScannerConnection.scanFile(activity.applicationContext, arrayOf(target.path), arrayOf(mime), null)
                }
                activity.runOnUiThread { result.success(mapOf("uri" to uri.toString())) }
            } catch (error: Exception) {
                activity.runOnUiThread { result.error("SAVE_AUDIO", "音乐保存失败，请检查可用空间与保存权限", null) }
            }
        }.start()
    }
}
