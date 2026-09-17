package dev.aeris.companion

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URI
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

data class Connection(val url: String = "", val token: String = "", val relayUrl: String = "", val relayToken: String = "") {
    val paired get() = url.isNotBlank() && token.isNotBlank()
    val hasRelay get() = relayUrl.isNotBlank() && relayToken.isNotBlank()
    fun validate() {
        validateEndpoint(url, BuildConfig.DEBUG)
        require(token.matches(Regex("[a-fA-F0-9]{64,}"))) { "Aeris token must be at least 64 hexadecimal characters." }
        if (relayUrl.isNotBlank() || relayToken.isNotBlank()) {
            validateEndpoint(relayUrl, BuildConfig.DEBUG)
            require(relayToken.matches(Regex("[a-fA-F0-9]{64,}"))) { "Wake relay token must be at least 64 hexadecimal characters." }
        }
    }
}

fun validateEndpoint(value: String, debug: Boolean) {
    val uri = try { URI(value) } catch (_: Exception) { throw IllegalArgumentException("Enter a valid HTTPS address.") }
    require(!uri.host.isNullOrBlank() && uri.userInfo == null && uri.rawQuery == null && uri.rawFragment == null && uri.path.orEmpty() in listOf("", "/")) { "Use a server address without a path, credentials, or query." }
    require(uri.scheme == "https" || (debug && uri.scheme == "http" && uri.host in listOf("10.0.2.2", "127.0.0.1", "localhost"))) { "Use HTTPS, such as your Tailscale Serve address." }
}

/** Android Keystore encrypts pairing data; no backup or log contains credentials. */
class PairingStore(context: Context) {
    private val prefs = context.getSharedPreferences("pairing", Context.MODE_PRIVATE)
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey("aeris-pairing", null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder("aeris-pairing", KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    fun read(): Connection {
        val encoded = prefs.getString("encrypted", null) ?: return Connection()
        val bytes = Base64.decode(encoded, Base64.NO_WRAP)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12))) }
        val data = JSONObject(String(cipher.doFinal(bytes.copyOfRange(12, bytes.size)), Charsets.UTF_8))
        return Connection(data.getString("url"), data.getString("token"), data.optString("relayUrl"), data.optString("relayToken"))
    }
    fun save(value: Connection) {
        val data = JSONObject().put("url",value.url).put("token",value.token).put("relayUrl",value.relayUrl).put("relayToken",value.relayToken)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE,key()) }
        val encrypted = cipher.doFinal(data.toString().toByteArray(Charsets.UTF_8))
        check(prefs.edit().putString("encrypted",Base64.encodeToString(cipher.iv + encrypted,Base64.NO_WRAP)).commit()) { "Could not save pairing." }
    }
}

class AerisApi {
    suspend fun request(config: Connection, path: String = "/v1/status", relay: Boolean = false, body: JSONObject? = null): JSONObject = withContext(Dispatchers.IO) {
        val endpoint = if (relay) config.relayUrl else config.url
        validateEndpoint(endpoint, BuildConfig.DEBUG)
        val conn = URI(endpoint.trimEnd('/') + path).toURL().openConnection() as HttpURLConnection
        try {
            conn.connectTimeout = 5000
            conn.readTimeout = if (path == "/v1/status") 5000 else 35000
            conn.instanceFollowRedirects = false
            conn.setRequestProperty("Authorization", "Bearer ${if (relay) config.relayToken else config.token}")
            conn.setRequestProperty("Accept", "application/json")
            conn.requestMethod = if (path == "/v1/status") "GET" else "POST"
            if (path == "/v1/poweroff") conn.setRequestProperty("X-Aeris-Confirm", "poweroff")
            if (body != null) {
                require(!relay && path in listOf("/v1/tomat", "/v1/workout/set"))
                val bytes=body.toString().toByteArray(Charsets.UTF_8)
                require(bytes.size <= 4096)
                conn.doOutput=true
                conn.setFixedLengthStreamingMode(bytes.size)
                conn.setRequestProperty("Content-Type", "application/json")
                conn.outputStream.use { it.write(bytes) }
            }
            val code = conn.responseCode
            if (code == 401) throw IllegalStateException("Pairing token rejected. Check connection settings.")
            if (code in 500..599) throw IOException("Aeris gateway is temporarily unavailable (HTTP $code).")
            val stream = if (code in 200..299) conn.inputStream else conn.errorStream
            val bytes = stream?.use { input ->
                val output = ByteArrayOutputStream()
                val buffer = ByteArray(8192)
                while (output.size() <= 262144) {
                    val count = input.read(buffer, 0, minOf(buffer.size,262145-output.size()))
                    if (count < 0) break
                    output.write(buffer,0,count)
                }
                output.toByteArray()
            } ?: ByteArray(0)
            check(bytes.size <= 262144) { "Server response is too large." }
            val json = try { JSONObject(String(bytes,Charsets.UTF_8)) } catch (_: Exception) { throw IllegalStateException("Unexpected server response (HTTP $code).") }
            check(code in 200..299 && json.optBoolean("ok")) { json.optString("error", "Request failed (HTTP $code).") }
            if (path == "/v1/status") check(json.optString("role") == if (relay) "relay" else "aeris") { "This address belongs to the wrong service." }
            json
        } finally { conn.disconnect() }
    }
}
