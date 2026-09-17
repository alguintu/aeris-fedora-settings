package dev.aeris.companion

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.launch

@Composable
internal fun UpdatesPanel(model: UpdateModel = viewModel()) {
    val context=LocalContext.current
    val scope=rememberCoroutineScope()
    var launching by remember { mutableStateOf(false) }
    val installer=rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { }
    val install: () -> Unit = {
        scope.launch {
            launching=true
            try { model.installerIntent()?.let { intent ->
                try { installer.launch(intent) } catch (_: Exception) { model.installationFailed() }
            } } finally { launching=false }
        }
    }
    val permission=rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) {
        if(context.packageManager.canRequestPackageInstalls()) install() else model.permissionDenied()
    }
    Card(colors=CardDefaults.cardColors(containerColor=MaterialTheme.colorScheme.surfaceVariant),modifier=Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {
            Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween) {
                Text("Updates",style=MaterialTheme.typography.titleMedium)
                Text(BuildConfig.VERSION_NAME,color=MaterialTheme.colorScheme.onSurfaceVariant)
            }
            when(val state=model.state) {
                UpdateState.Checking -> LinearProgressIndicator(Modifier.fillMaxWidth())
                is UpdateState.Downloading -> {
                    if(state.percent < 0) LinearProgressIndicator(Modifier.fillMaxWidth())
                    else LinearProgressIndicator(progress={state.percent/100f},modifier=Modifier.fillMaxWidth())
                    TextButton(onClick=model::cancel) { Text("Cancel download") }
                }
                is UpdateState.Available -> Button(onClick={model.downloadUpdate(state.release)}) { Text("Download ${state.release.version}") }
                is UpdateState.Ready -> {
                    state.notice?.let { Text(it,color=MaterialTheme.colorScheme.error,style=MaterialTheme.typography.bodySmall) }
                    Row(horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                        Button(enabled=!launching,onClick={
                            if(context.packageManager.canRequestPackageInstalls()) install()
                            else try {
                                permission.launch(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,Uri.parse("package:${context.packageName}")))
                            } catch (_: Exception) { model.permissionDenied() }
                        }) { Text("Install ${state.version}") }
                        TextButton(enabled=!launching,onClick=model::cancel) { Text("Discard") }
                    }
                }
                else -> {
                    when(state) {
                        UpdateState.Current -> Text("Up to date",style=MaterialTheme.typography.bodyMedium)
                        UpdateState.Empty -> Text("No releases yet",style=MaterialTheme.typography.bodyMedium)
                        is UpdateState.Failed -> Text(state.message,color=MaterialTheme.colorScheme.error,style=MaterialTheme.typography.bodySmall)
                        else -> Unit
                    }
                    OutlinedButton(onClick=model::check) { Text("Check for updates") }
                }
            }
        }
    }
}
