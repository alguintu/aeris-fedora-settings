package dev.aeris.companion

import org.junit.Assert.*
import org.junit.Test

class DriveUpdatesTest {
    private fun entry(name: String, link: String) = """<div class="flip-entry"><a href="$link"><div class="flip-entry-title">$name</div></a></div>"""
    private fun listing(vararg entries: String) = "<div class='flip-entries'>${entries.joinToString("")}</div>"

    @Test fun newestVersionWinsRatherThanFilenameOrListingOrder() {
        val releases=parseDriveReleases(listing(
            entry("aeris-companion-0.1.9.apk","https://drive.google.com/file/d/old/view"),
            entry("aeris-companion-0.1.10.apk","https://drive.google.com/file/d/new/view?resourcekey=key_1"),
            entry("notes.txt","https://drive.google.com/file/d/notes/view"),
            entry("aeris-companion-0.1.2.apk","https://drive.google.com/open?id=older")
        ))
        assertEquals(listOf("0.1.10","0.1.9","0.1.2"),releases.map { it.version.toString() })
        assertTrue(releases.first().downloadUrl.endsWith("resourcekey=key_1"))
    }
    @Test fun privateOrChangedDrivePageIsNotReportedAsUpToDate() {
        assertTrue(parseDriveReleases(listing()).isEmpty())
        assertThrows(IllegalStateException::class.java) { parseDriveReleases("<html>Sign in</html>") }
    }
    @Test fun forgedFileLinksAndUnversionedApksAreIgnored() {
        assertTrue(parseDriveReleases(listing(
            entry("aeris-companion-9.0.0.apk","https://drive.google.com.attacker.test/file/d/evil/view"),
            entry("aeris-companion-9.0.0.apk","http://drive.google.com/file/d/evil/view"),
            entry("aeris-companion-9.0.0.apk","https://attacker@drive.google.com/file/d/evil/view"),
            entry("app-debug.apk","https://drive.google.com/file/d/unknown/view")
        )).isEmpty())
    }
    @Test fun redirectsCannotEscapeGoogleDownloadHostsOrTls() {
        trustedDriveUrl("https://drive.usercontent.google.com/download?id=example")
        trustedDriveUrl("https://doc-abc.googleusercontent.com/download")
        for(url in listOf("http://drive.google.com/file","https://drive.google.com.evil.test/file","https://googleusercontent.com.evil.test/file","file:///tmp/test","https://user@drive.google.com/file","https://drive.google.com:8443/file","https://accounts.google.com/login")) {
            assertThrows(IllegalArgumentException::class.java) { trustedDriveUrl(url) }
        }
    }
    @Test fun confirmationPreservesFileIdentityAndEncodesFields() {
        val html="""<form id="download-form" action="https://drive.usercontent.google.com/download" method="get"><input name="id" value="file1"><input name="export" value="download"><input name="confirm" value="t"><input name="uuid" value="a&amp;b"></form>"""
        assertTrue(driveConfirmation(html,UPDATE_LIST,"file1").contains("uuid=a%26b"))
        assertThrows(IllegalStateException::class.java) { driveConfirmation(html,UPDATE_LIST,"other") }
        assertThrows(IllegalArgumentException::class.java) { driveConfirmation(html.replace("drive.usercontent.google.com","evil.test"),UPDATE_LIST,"file1") }
    }
    @Test fun apkMustBeNewerAndMatchBothPackageAndSigner() {
        validateUpdateIdentity("dev.aeris.companion",3,setOf("signer"),"dev.aeris.companion",4,setOf("signer"))
        for(code in listOf(2L,3L)) assertThrows(IllegalStateException::class.java) {
            validateUpdateIdentity("dev.aeris.companion",3,setOf("signer"),"dev.aeris.companion",code,setOf("signer"))
        }
        assertThrows(IllegalStateException::class.java) { validateUpdateIdentity("aeris",3,setOf("signer"),"other",4,setOf("signer")) }
        assertThrows(IllegalStateException::class.java) { validateUpdateIdentity("aeris",3,setOf("signer"),"aeris",4,setOf("different")) }
        assertThrows(IllegalStateException::class.java) { validateUpdateIdentity("aeris",3,emptySet(),"aeris",4,emptySet()) }
    }
    @Test fun malformedAndOverflowingVersionsAreRejected() {
        for(version in listOf("1.2", "1.2.3.4", "-1.2.3", "1.2.beta", "999999999999.0.1")) assertNull(AppVersion.parse(version))
    }
}
