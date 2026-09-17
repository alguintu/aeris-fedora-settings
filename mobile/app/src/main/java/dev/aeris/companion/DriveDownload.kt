package dev.aeris.companion

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.io.File
import java.net.HttpURLConnection
import java.net.URI

internal class DriveDownload(private val open: (String) -> HttpURLConnection = { URI(it).toURL().openConnection() as HttpURLConnection }) {
    private fun readBounded(input: InputStream, limit: Int): ByteArray {
        val out=ByteArrayOutputStream()
        val buffer=ByteArray(8192)
        while(out.size() <= limit) {
            val count=input.read(buffer,0,minOf(buffer.size,limit+1-out.size()))
            if(count < 0) break
            out.write(buffer,0,count)
        }
        return out.toByteArray()
    }
    private fun connect(address: String): HttpURLConnection {
        var url = address
        repeat(8) {
            val conn = open(trustedDriveUrl(url).toString())
            conn.connectTimeout = 15_000
            conn.readTimeout = 20_000
            conn.instanceFollowRedirects = false
            conn.useCaches = false
            conn.setRequestProperty("User-Agent", "Aeris-Companion/${BuildConfig.VERSION_NAME}")
            try {
                val code = conn.responseCode
                if (code in setOf(301,302,303,307,308)) {
                    val location = conn.getHeaderField("Location") ?: error("Drive returned an invalid redirect.")
                    url = URI(url).resolve(location).toString()
                    conn.disconnect()
                } else {
                    check(code in 200..299) { "Drive is unavailable (HTTP $code). Try again later." }
                    return conn
                }
            } catch (error: Exception) { conn.disconnect(); throw error }
        }
        error("Too many Drive redirects.")
    }
    suspend fun releases(): List<DriveRelease> = withContext(Dispatchers.IO) {
        currentCoroutineContext().ensureActive()
        val conn = connect(UPDATE_LIST)
        try {
            val bytes = conn.inputStream.use { readBounded(it,2_000_000) }
            check(bytes.size <= 2_000_000) { "Drive folder listing is too large." }
            parseDriveReleases(bytes.toString(Charsets.UTF_8))
        } finally { conn.disconnect() }
    }
    suspend fun download(release: DriveRelease, destination: File, progress: suspend (Int) -> Unit) = withContext(Dispatchers.IO) {
        val partial = File(destination.parentFile, "${destination.name}.part")
        partial.delete()
        try {
            var url = release.downloadUrl
            repeat(3) {
                currentCoroutineContext().ensureActive()
                val conn = connect(url)
                try {
                    if (conn.contentType.orEmpty().contains("text/html", ignoreCase=true)) {
                        val html = conn.inputStream.use { readBounded(it,1_000_000) }
                        check(html.size <= 1_000_000) { "Unexpected Drive response." }
                        url = driveConfirmation(html.toString(Charsets.UTF_8),conn.url.toString(),release.fileId)
                    } else {
                        val limit = 80L * 1024 * 1024
                        val total = conn.contentLengthLong
                        check(total <= limit) { "The update exceeds the 80 MB limit." }
                        var received = 0L
                        var reported = -2
                        conn.inputStream.use { input ->
                            partial.outputStream().use { output ->
                                val buffer = ByteArray(64 * 1024)
                                while (true) {
                                    currentCoroutineContext().ensureActive()
                                    val count = input.read(buffer)
                                    if (count < 0) break
                                    received += count
                                    check(received <= limit) { "The update exceeds the 80 MB limit." }
                                    output.write(buffer,0,count)
                                    val percent = if(total > 0) ((received*100/total).toInt()).coerceAtMost(100) else -1
                                    if (percent != reported) { progress(percent); reported=percent }
                                }
                            }
                        }
                        check(received > 0 && (total < 0 || received == total)) { "The download was interrupted. Try again." }
                        check(partial.renameTo(destination)) { "Could not save the update." }
                        return@withContext
                    }
                } finally { conn.disconnect() }
            }
            error("Drive could not provide the APK. Try again later.")
        } finally { partial.delete() }
    }
}
