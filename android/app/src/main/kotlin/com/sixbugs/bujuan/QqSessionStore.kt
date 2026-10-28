// Community maintenance and new features: tiancaiProgramer.
package com.sixbugs.bujuan

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Device-bound encrypted session, stored in the backup-excluded app directory. */
class QqSessionStore(private val context: Context) {
    private val file get() = java.io.File(context.noBackupFilesDir,"qqmusic-session.bin")
    private var memory: String? = null
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val alias = "buyu.qqmusic.session"
        (store.getKey(alias,null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,"AndroidKeyStore")
        generator.init(KeyGenParameterSpec.Builder(alias,KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        return generator.generateKey()
    }
    fun save(value: String) {
        require(value.length <= 65536 && !value.contains('\n') && !value.contains('\r'))
        if (Build.VERSION.SDK_INT < 23) { memory = value; return }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE,key()) }
        val encrypted = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        val staged = java.io.File(context.noBackupFilesDir,"qqmusic-session.tmp")
        try {
            staged.outputStream().use { it.write(cipher.iv.size); it.write(cipher.iv); it.write(encrypted) }
            check(staged.renameTo(file))
        } finally { staged.delete() }
    }
    fun read(): String? {
        if (Build.VERSION.SDK_INT < 23) return memory
        if (!file.exists()) return null
        return try {
            val bytes = file.readBytes(); val n = bytes[0].toInt() and 255
            require(n == 12 && bytes.size > n+17)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.DECRYPT_MODE,key(),GCMParameterSpec(128,bytes.copyOfRange(1,n+1))) }
            cipher.doFinal(bytes.copyOfRange(n+1,bytes.size)).toString(Charsets.UTF_8)
        } catch (_: Exception) { file.delete(); null }
    }
    fun clear() { memory = null; file.delete() }
}
