package dev.aeris.companion

import org.jsoup.Jsoup
import java.net.URI
import java.net.URLDecoder
import java.net.URLEncoder

internal const val UPDATE_FOLDER = "https://drive.google.com/drive/folders/1YrDgjdrF_TVoKSSzqK14nAo45tfBIngk"
internal const val UPDATE_LIST = "https://drive.google.com/embeddedfolderview?id=1YrDgjdrF_TVoKSSzqK14nAo45tfBIngk"

internal data class AppVersion(val major: Int, val minor: Int, val patch: Int) : Comparable<AppVersion> {
    override fun compareTo(other: AppVersion): Int = compareValuesBy(this, other, { it.major }, { it.minor }, { it.patch })
    override fun toString() = "$major.$minor.$patch"
    companion object {
        fun parse(value: String): AppVersion? {
            val parts = value.split('.')
            if (parts.size != 3 || parts.any { !it.matches(Regex("[0-9]{1,9}")) }) return null
            return AppVersion(parts[0].toInt(), parts[1].toInt(), parts[2].toInt())
        }
    }
}
internal data class DriveRelease(val version: AppVersion, val fileId: String, val resourceKey: String?) {
    val downloadUrl get() = "https://drive.usercontent.google.com/download?id=$fileId&export=download" +
        (resourceKey?.let { "&resourcekey=${encode(it)}" } ?: "")
}
internal fun encode(value: String): String = URLEncoder.encode(value, "UTF-8")
private fun query(uri: URI): Map<String, String> = uri.rawQuery.orEmpty().split('&').mapNotNull {
    val parts = it.split('=', limit=2)
    if (parts.size == 2) URLDecoder.decode(parts[0], "UTF-8") to URLDecoder.decode(parts[1], "UTF-8") else null
}.toMap()

/** Parse only Drive's public embedded listing, never execute its scripts. */
internal fun parseDriveReleases(html: String): List<DriveRelease> {
    val document = Jsoup.parse(html, UPDATE_LIST)
    check(document.selectFirst(".flip-entries") != null) { "Drive folder unavailable. Check its sharing settings." }
    return document.select(".flip-entry").mapNotNull { entry ->
        val name = entry.selectFirst(".flip-entry-title")?.text()?.trim() ?: return@mapNotNull null
        val match = Regex("aeris-companion-([0-9]+\\.[0-9]+\\.[0-9]+)\\.apk").matchEntire(name) ?: return@mapNotNull null
        val version = AppVersion.parse(match.groupValues[1]) ?: return@mapNotNull null
        val link = entry.selectFirst("a[href]")?.attr("href") ?: return@mapNotNull null
        val uri = runCatching { URI(UPDATE_LIST).resolve(link) }.getOrNull() ?: return@mapNotNull null
        if (uri.scheme != "https" || uri.host != "drive.google.com" || uri.userInfo != null || uri.port != -1) return@mapNotNull null
        val params = query(uri)
        val id = Regex("/file/d/([A-Za-z0-9_-]+)/.*").matchEntire(uri.path)?.groupValues?.get(1)
            ?: if(uri.path == "/open") params["id"] else null
        if (id == null || !id.matches(Regex("[A-Za-z0-9_-]{1,200}"))) return@mapNotNull null
        val key = params["resourcekey"]?.takeIf { it.matches(Regex("[A-Za-z0-9_-]{1,256}")) }
        DriveRelease(version, id, key)
    }.distinct().sortedWith(compareByDescending<DriveRelease> { it.version }.thenBy { it.fileId })
}

internal fun trustedDriveUrl(value: String): URI {
    val uri = URI(value)
    val host = uri.host.orEmpty().lowercase()
    require(uri.scheme == "https" && uri.userInfo == null && uri.port in listOf(-1,443) &&
        (host in setOf("drive.google.com", "drive.usercontent.google.com") || host.endsWith(".googleusercontent.com"))) {
        "Drive returned an unsupported download address."
    }
    return uri
}

/** Google may present a download-confirmation form instead of APK bytes. */
internal fun driveConfirmation(html: String, base: String, fileId: String): String {
    val form = Jsoup.parse(html, base).selectFirst("form#download-form")
        ?: error("Drive could not provide the APK. Try again later.")
    check(form.attr("method").equals("get", ignoreCase=true)) { "Unsupported Drive download response." }
    val action = trustedDriveUrl(URI(base).resolve(form.attr("action")).toString())
    check(action.host == "drive.usercontent.google.com" && action.path == "/download") { "Unsupported Drive download response." }
    val fields = form.select("input[name]").associate { it.attr("name") to it.attr("value") }
    check(fields["id"] == fileId && fields["export"] == "download") { "Drive returned a different file." }
    return URI(action.scheme, action.authority, action.path, null, null).toString() + "?" +
        fields.entries.joinToString("&") { "${encode(it.key)}=${encode(it.value)}" }
}

internal fun validateUpdateIdentity(packageName: String, installedCode: Long, installedSigners: Set<String>,
    candidatePackage: String, candidateCode: Long, candidateSigners: Set<String>) {
    check(candidatePackage == packageName) { "This APK is not Aeris." }
    check(candidateCode > installedCode) { "This update is not newer than the installed app." }
    check(installedSigners.isNotEmpty() && candidateSigners == installedSigners) { "This APK was signed with a different key." }
}
