package dev.aeris.companion

import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.ByteArrayInputStream
import java.io.IOException
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL

class DriveDownloadTest {
    @get:Rule val temporary=TemporaryFolder()
    private val release=DriveRelease(AppVersion(0,1,9),"file1",null)
    private class Response(address: String, val body: ByteArray, val status: Int=200,
        val mime: String="application/vnd.android.package-archive", val location: String?=null,
        val length: Long=body.size.toLong(), val broken: Boolean=false) : HttpURLConnection(URL(address)) {
        var closed=false
        override fun getResponseCode()=status
        override fun getContentType()=mime
        override fun getContentLengthLong()=length
        override fun getHeaderField(name: String)=if(name == "Location") location else null
        override fun getInputStream(): InputStream = if(broken) object: InputStream() {
            override fun read(): Int = throw IOException("Connection lost")
        } else ByteArrayInputStream(body)
        override fun disconnect() { closed=true }
        override fun connect() {}
        override fun usingProxy()=false
    }
    @Test fun followsGoogleConfirmationThenSavesCompleteDownload() = runBlocking {
        val html="""<form id="download-form" action="https://drive.usercontent.google.com/download" method="get"><input name="id" value="file1"><input name="export" value="download"><input name="confirm" value="t"></form>"""
        val requests=mutableListOf<Response>()
        val bytes=ByteArray(150000) { (it%251).toByte() }
        val client=DriveDownload { address ->
            Response(address,if(requests.isEmpty()) html.toByteArray() else bytes,mime=if(requests.isEmpty()) "text/html" else "application/octet-stream").also { requests+=it }
        }
        val file=temporary.root.resolve("update.apk")
        val progress=mutableListOf<Int>()
        client.download(release,file) { progress+=it }
        assertArrayEquals(bytes,file.readBytes())
        assertEquals(100,progress.last())
        assertEquals(2,requests.size)
        assertTrue(requests.all { it.closed })
        assertFalse(temporary.root.resolve("update.apk.part").exists())
    }
    @Test fun redirectIsValidatedBeforeAnotherConnection() = runBlocking {
        var count=0
        val client=DriveDownload { url -> count++; Response(url,byteArrayOf(),302,location="http://127.0.0.1/private") }
        val file=temporary.root.resolve("update.apk")
        try { client.download(release,file) {}; fail("Unsafe redirect accepted") } catch (_: IllegalArgumentException) {}
        assertEquals(1,count)
        assertFalse(file.exists())
    }
    @Test fun incompleteOversizedAndBrokenTransfersNeverLeaveAnInstallableFile() = runBlocking {
        for(kind in listOf("short","oversized","broken")) {
            val client=DriveDownload { url -> Response(url,byteArrayOf(1,2,3),length=if(kind=="oversized") 90L*1024*1024 else 10,broken=kind=="broken") }
            val file=temporary.root.resolve("$kind.apk")
            try { client.download(release,file) {}; fail("$kind transfer accepted") } catch (_: Exception) {}
            assertFalse(file.exists())
            assertFalse(temporary.root.resolve("$kind.apk.part").exists())
        }
    }
    @Test fun signInHtmlIsNotSavedAsAnApk() = runBlocking {
        val client=DriveDownload { url -> Response(url,"<html>Sign in</html>".toByteArray(),mime="text/html") }
        val file=temporary.root.resolve("update.apk")
        try { client.download(release,file) {}; fail("HTML accepted") } catch (_: IllegalStateException) {}
        assertFalse(file.exists())
    }
}
