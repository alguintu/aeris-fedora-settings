package dev.aeris.companion

import android.app.Application
import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.FileProvider
import androidx.core.content.pm.PackageInfoCompat
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import java.util.UUID
import kotlinx.coroutines.withContext
import java.io.File
import java.io.IOException
import java.security.MessageDigest

internal sealed interface UpdateState {
    data object Idle : UpdateState
    data object Checking : UpdateState
    data object Current : UpdateState
    data object Empty : UpdateState
    data class Available(val release: DriveRelease) : UpdateState
    data class Downloading(val percent: Int) : UpdateState
    data class Ready(val version: String, val notice: String? = null) : UpdateState
    data class Failed(val message: String) : UpdateState
}

internal class UpdateModel(application: Application) : AndroidViewModel(application) {
    var state by mutableStateOf<UpdateState>(UpdateState.Idle); private set
    private val download = DriveDownload()
    private val directory = File(application.cacheDir,"updates").apply { mkdirs() }
    private val apk = File(directory,"aeris-update.apk")
    private var task: Job? = null
    private val busy get() = state == UpdateState.Checking || state is UpdateState.Downloading

    init {
        if (apk.exists()) {
            state=UpdateState.Checking
            task=viewModelScope.launch {
                state=try { UpdateState.Ready(validateApk(apk)) } catch(cancel: CancellationException) { throw cancel } catch (_: Exception) { apk.delete(); UpdateState.Idle }
            }
        }
    }
    fun check() {
        if(busy) return
        state=UpdateState.Checking
        task=viewModelScope.launch {
            try {
                val latest=download.releases().firstOrNull()
                state=when {
                    latest == null -> UpdateState.Empty
                    latest.version <= AppVersion.parse(BuildConfig.VERSION_NAME)!! -> UpdateState.Current
                    else -> UpdateState.Available(latest)
                }
            } catch(cancel: CancellationException) { throw cancel }
            catch(error: Exception) { fail(error) }
        }
    }
    fun downloadUpdate(release: DriveRelease) {
        if(busy) return
        state=UpdateState.Downloading(-1)
        task=viewModelScope.launch {
            val candidate=File(directory,"candidate-${UUID.randomUUID()}.apk")
            try {
                download.download(release,candidate) { percent ->
                    withContext(Dispatchers.Main) { state=UpdateState.Downloading(percent) }
                }
                val version=validateApk(candidate)
                check(version == release.version.toString()) { "The APK version does not match its filename." }
                currentCoroutineContext().ensureActive()
                apk.delete()
                check(candidate.renameTo(apk)) { "Could not save the update." }
                state=UpdateState.Ready(version)
            } catch(cancel: CancellationException) { throw cancel }
            catch(error: Exception) { currentCoroutineContext().ensureActive(); fail(error) }
            finally { candidate.delete() }
        }
    }
    fun cancel() { task?.cancel(); apk.delete(); state=UpdateState.Idle }
    fun permissionDenied() {
        val ready=state as? UpdateState.Ready ?: return
        state=ready.copy(notice="Allow installs from Aeris to continue.")
    }
    fun installationFailed() {
        val ready=state as? UpdateState.Ready ?: return
        state=ready.copy(notice="Android could not open the installer.")
    }
    suspend fun installerIntent(): Intent? {
        if(state !is UpdateState.Ready) return null
        return try {
            val version=validateApk(apk)
            val context=getApplication<Application>()
            val uri=FileProvider.getUriForFile(context,"${context.packageName}.updates",apk)
            state=UpdateState.Ready(version)
            Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri,"application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                clipData=ClipData.newRawUri("Aeris update",uri)
            }
        } catch(cancel: CancellationException) { throw cancel }
        catch(error: Exception) { apk.delete(); fail(error); null }
    }
    private fun fail(error: Exception) {
        state=UpdateState.Failed(if(error is IOException) "Connection failed. Try again." else error.message ?: "Update failed. Try again.")
    }
    @Suppress("DEPRECATION")
    private suspend fun validateApk(file: File): String = withContext(Dispatchers.IO) {
        val context=getApplication<Application>()
        val pm=context.packageManager
        val flags=if(Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
        val candidate=pm.getPackageArchiveInfo(file.absolutePath,flags) ?: error("The downloaded file is not a valid APK.")
        val installed=pm.getPackageInfo(context.packageName,flags)
        validateUpdateIdentity(context.packageName,PackageInfoCompat.getLongVersionCode(installed),signers(installed),
            candidate.packageName,PackageInfoCompat.getLongVersionCode(candidate),signers(candidate))
        candidate.versionName ?: error("The APK has no version.")
    }
    @Suppress("DEPRECATION")
    private fun signers(info: PackageInfo): Set<String> {
        val signatures=if(Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures
        return signatures.orEmpty().map { signature ->
            MessageDigest.getInstance("SHA-256").digest(signature.toByteArray()).joinToString("") { "%02x".format(it) }
        }.toSet()
    }
}
