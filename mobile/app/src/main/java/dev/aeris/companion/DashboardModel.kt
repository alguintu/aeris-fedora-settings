package dev.aeris.companion

import android.app.Application
import android.os.SystemClock
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONObject
import java.io.IOException

class DashboardModel(application: Application) : AndroidViewModel(application) {
    private val store = PairingStore(application)
    private val api = AerisApi()
    private val requests = Mutex()
    var message by mutableStateOf(""); private set
    var connection by mutableStateOf(try { store.read() } catch (_: Exception) { message = "Saved pairing could not be unlocked. Please pair again."; Connection() }); private set
    private var snapshot by mutableStateOf<StatusSnapshot<JSONObject>?>(null)
    val status: JSONObject? get() = snapshot?.payload
    var connectionError by mutableStateOf(""); private set
    var busy by mutableStateOf(false); private set
    var settings by mutableStateOf(!connection.paired)
    var savedSetRequestId by mutableStateOf(""); private set
    var workoutError by mutableStateOf(""); private set
    fun clearMessage(shown: String) { if(message == shown) message="" }
    fun isReachable(clock: Long): Boolean = snapshot?.isFresh(clock) == true
    fun save(value: Connection) {
        try {
            value.validate(); store.save(value); connection=value
            snapshot=null; connectionError=""; settings=false; message="Connection saved."
            viewModelScope.launch { refresh() }
        } catch (error: Exception) { message=error.message ?: "Could not save connection." }
    }
    suspend fun refresh(force: Boolean = false) {
        if (!connection.paired || (busy && !force)) return
        requests.withLock {
            val selected=connection
            try {
                val data=api.request(selected)
                if (selected == connection) { snapshot=StatusSnapshot(data,SystemClock.elapsedRealtime()); connectionError="" }
            } catch (cancel: CancellationException) { throw cancel }
            catch (error: Exception) {
                if (selected == connection) {
                    // Keep the last good reading through brief transport failures,
                    // but never extend its expiry or keep rejected pairing data.
                    if (error !is IOException) snapshot=null
                    connectionError=error.message ?: "Aeris is unreachable."
                }
            }
        }
    }
    fun action(path: String, relay: Boolean = false, body: JSONObject? = null) {
        if (busy) return
        busy=true
        workoutError=""
        viewModelScope.launch {
            requests.withLock {
                try {
                    val result=api.request(connection,path,relay,body)
                    if(path == "/v1/workout/set") savedSetRequestId=body?.optString("request_id").orEmpty()
                    if(body == null) message=result.optString("message").ifBlank { "Mode applied." }
                    if (path == "/v1/poweroff") snapshot=null
                } catch (cancel: CancellationException) { throw cancel }
                catch (error: Exception) {
                    if(path == "/v1/workout/set") workoutError=error.message ?: "Could not save set."
                    else message="${error.message ?: "Request failed."} Check status before trying again."
                }
            }
            try { refresh(force=true) } finally { busy=false }
        }
    }
    fun service(name: String, clock: Long): JSONObject? {
        val current=snapshot ?: return null
        val root=current.payload
        val entry=root.optJSONObject("services")?.optJSONObject(name) ?: return null
        if (!current.serviceIsFresh(root.optLong("server_time"),entry.optLong("updated_at"),clock)) return null
        return entry.optJSONObject("payload")?.takeIf { it.optBoolean("ok") }
    }
    fun serviceAgeMillis(name: String, clock: Long): Long {
        val current=snapshot ?: return 0
        val entry=current.payload.optJSONObject("services")?.optJSONObject(name) ?: return 0
        return ((current.payload.optLong("server_time")-entry.optLong("updated_at")).coerceAtLeast(0)*1000)+current.ageMillis(clock)
    }
    fun clearWorkoutError() { workoutError="" }
}
