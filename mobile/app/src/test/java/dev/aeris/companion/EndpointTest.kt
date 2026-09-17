package dev.aeris.companion
import org.junit.Test
import org.junit.Assert.*

class EndpointTest {
    @Test fun credentialsRequireEncryptedTransport() {
        validateEndpoint("https://aeris.example.ts.net",false)
        for (url in listOf("http://aeris.example.ts.net","http://192.168.5.115:4280","https://token@aeris.test","https://aeris.test?token=secret","https://aeris.test/v1/status","file:///tmp/test")) {
            assertThrows(IllegalArgumentException::class.java) { validateEndpoint(url,false) }
        }
    }
    @Test fun debugCleartextIsLimitedToEmulatorOrLoopback() {
        validateEndpoint("http://10.0.2.2:4280",true)
        assertThrows(IllegalArgumentException::class.java) { validateEndpoint("http://192.168.5.115:4280",true) }
        assertThrows(IllegalArgumentException::class.java) { validateEndpoint("http://10.0.2.2:4280",false) }
    }
}
