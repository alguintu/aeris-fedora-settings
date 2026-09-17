package dev.aeris.companion

import android.os.Bundle
import android.os.SystemClock
import androidx.activity.compose.BackHandler
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.SystemBarStyle
import androidx.compose.foundation.background
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.annotation.DrawableRes
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.delay
import org.json.JSONObject
import java.util.Locale

private val Surface=Color(0xFF2E3440)
private val Raised=Color(0xFF3B4252)
private val Cyan=Color(0xFF88C0D0)
private val Green=Color(0xFFA3BE8C)
private val Muted=Color(0xFFA7ADBA)
private val Red=Color(0xFFBF616A)

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge(statusBarStyle=SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),navigationBarStyle=SystemBarStyle.dark(android.graphics.Color.TRANSPARENT))
        setContent {
            MaterialTheme(colorScheme=darkColorScheme(primary=Cyan,onPrimary=Surface,secondary=Green,secondaryContainer=Color(0xFF45606E),onSecondaryContainer=Color(0xFFE5E9F0),background=Surface,surface=Surface,surfaceVariant=Raised,onSurfaceVariant=Muted,outline=Muted.copy(alpha=0.5f),onBackground=Color(0xFFE5E9F0),onSurface=Color(0xFFE5E9F0),error=Red)) {
                androidx.compose.material3.Surface(modifier=Modifier.fillMaxSize(),color=Surface) { Companion() }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Companion(model: DashboardModel = viewModel()) {
    val lifecycle=LocalLifecycleOwner.current.lifecycle
    var clock by remember { mutableLongStateOf(SystemClock.elapsedRealtime()) }
    var shutdown by rememberSaveable { mutableStateOf(false) }
    val snackbar = remember { SnackbarHostState() }
    BackHandler(enabled=model.settings && model.connection.paired) { model.settings=false }
    LaunchedEffect(model.message) {
        val message=model.message
        if(message.isNotBlank()) { snackbar.showSnackbar(message); model.clearMessage(message) }
    }
    LaunchedEffect(lifecycle,model.connection) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
            while (true) { model.refresh(); delay(2000) }
        }
    }
    LaunchedEffect(lifecycle) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
            while (true) { clock=SystemClock.elapsedRealtime(); delay(1000) }
        }
    }
    val reachable=model.isReachable(clock)
    Scaffold(
        modifier=Modifier.fillMaxSize().safeDrawingPadding(),
        containerColor=Surface,
        contentWindowInsets=WindowInsets(0,0,0,0),
        snackbarHost={SnackbarHost(snackbar)},
        topBar={
            Column {
                Row(Modifier.fillMaxWidth().height(56.dp).padding(horizontal=16.dp),verticalAlignment=Alignment.CenterVertically) {
                    if(model.settings) {
                        if(model.connection.paired) IconButton(onClick={model.settings=false}) {
                            Icon(painterResource(R.drawable.ic_chevron_down),contentDescription="Back",modifier=Modifier.size(22.dp).rotate(90f))
                        }
                        Text("Settings",style=MaterialTheme.typography.titleLarge)
                    } else {
                        Icon(painterResource(R.drawable.ic_aeris_wordmark),contentDescription="Aeris",tint=MaterialTheme.colorScheme.onSurface,modifier=Modifier.width(128.dp).height(30.dp))
                        Spacer(Modifier.weight(1f))
                        IconButton(onClick={model.settings=true},enabled=!model.busy) {
                            Icon(painterResource(R.drawable.ic_connection),contentDescription="Settings",tint=Cyan,modifier=Modifier.size(22.dp))
                        }
                    }
                }
                Box(Modifier.fillMaxWidth().height(2.dp)) {
                    if(model.busy) LinearProgressIndicator(Modifier.fillMaxWidth())
                }
            }
        }
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(horizontal=16.dp,vertical=8.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
            if(model.settings) {
                UpdatesPanel()
                Pairing(model)
            } else {
                PowerTile(model,reachable,onShutdown={shutdown=true})
                val metrics=model.service("metrics",clock)?.optJSONObject("data")
                ResourceTiles(metrics)
                PomodoroPanel(model,clock)
                ModePanel("LIGHTING","rgb",listOf("work" to "Work","night" to "Night","day" to "Day","off" to "Off","party" to "Party"),model,clock)
                ModePanel("COOLING","cooling",listOf("default" to "Default","quiet" to "Quiet","performance" to "Performance","firmware" to "BIOS"),model,clock)
                ModePanel("AWAKE","awake",listOf("normal" to "Normal","system" to "System","full" to "Full"),model,clock)
            }
        }
    }
    if(shutdown) AlertDialog(onDismissRequest={shutdown=false},title={Text("Shut down Aeris?")},text={Text("Unsaved work may be lost.")},confirmButton={TextButton(onClick={shutdown=false;model.action("/v1/poweroff")},enabled=reachable && !model.busy){Text("Shut down",color=Red)}},dismissButton={TextButton(onClick={shutdown=false}){Text("Cancel")}})
}

@Composable private fun Panel(content: @Composable ColumnScope.() -> Unit) {
    Card(colors=CardDefaults.cardColors(containerColor=Raised,contentColor=MaterialTheme.colorScheme.onSurface),modifier=Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp),verticalArrangement=Arrangement.spacedBy(12.dp),content=content)
    }
}
@Composable private fun DashboardIcon(@DrawableRes icon: Int, tint: Color = LocalContentColor.current) {
    Icon(painterResource(icon),contentDescription=null,tint=tint,modifier=Modifier.size(18.dp))
}
@Composable private fun Label(text: String, @DrawableRes icon: Int? = null) {
    Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(7.dp)) {
        if(icon != null) DashboardIcon(icon,tint=Muted)
        Text(text,color=Muted,fontFamily=FontFamily.Monospace,fontSize=12.sp,letterSpacing=1.6.sp)
    }
}
@Composable private fun PowerTile(model: DashboardModel, reachable: Boolean, onShutdown: () -> Unit) {
    val fontScale=LocalDensity.current.fontScale
    Tile {
        BoxWithConstraints {
            if(maxWidth/fontScale < 260.dp) {
                Column {
                    PowerStatus(reachable)
                    Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.End,verticalAlignment=Alignment.CenterVertically) {
                        PowerActions(model,reachable,onShutdown)
                    }
                }
            } else {
                Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically) {
                    PowerStatus(reachable)
                    Spacer(Modifier.weight(1f))
                    PowerActions(model,reachable,onShutdown)
                }
            }
        }
    }
}
@Composable private fun PowerStatus(reachable: Boolean) {
    // Background polls never introduce a transitional availability label.
    Row(Modifier.heightIn(min=48.dp),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(8.dp)) {
        DashboardIcon(R.drawable.ic_power,tint=if(reachable) Green else Muted)
        Text(if(reachable) "Online" else "Off",style=MaterialTheme.typography.titleMedium)
    }
}
@Composable private fun PowerActions(model: DashboardModel, reachable: Boolean, onShutdown: () -> Unit) {
    TextButton(onClick={if(model.connection.hasRelay) model.action("/v1/wake",true) else model.settings=true},enabled=!model.busy) {
        DashboardIcon(R.drawable.ic_zap); Spacer(Modifier.width(4.dp)); Text(if(model.connection.hasRelay) "Wake" else "Set up wake")
    }
    IconButton(onClick=onShutdown,enabled=reachable && !model.busy && model.status?.optBoolean("shutdown_enabled") == true) {
        Icon(painterResource(R.drawable.ic_power),contentDescription="Shut down",modifier=Modifier.size(20.dp))
    }
}

/** Compact dashboard surfaces; pairing forms retain their roomier Panel spacing. */
@Composable private fun Tile(modifier: Modifier=Modifier, content: @Composable ColumnScope.() -> Unit) {
    Card(modifier=modifier.fillMaxWidth(),shape=RoundedCornerShape(12.dp),colors=CardDefaults.cardColors(containerColor=Raised,contentColor=MaterialTheme.colorScheme.onSurface)) {
        Column(Modifier.padding(12.dp),verticalArrangement=Arrangement.spacedBy(8.dp),content=content)
    }
}
@Composable private fun ResourceTiles(metrics: JSONObject?) {
    val fontScale=LocalDensity.current.fontScale
    BoxWithConstraints {
        // Keep large system text readable instead of squeezing two tiny columns.
        if(maxWidth/fontScale < 260.dp) {
            Column(verticalArrangement=Arrangement.spacedBy(8.dp)) {
                ResourceTile("CPU", "RAM", R.drawable.ic_processor, metrics, "cpu", "ram", Cyan)
                ResourceTile("GPU", "VRAM", R.drawable.ic_graphics_card, metrics, "gpu", "vram", Green)
            }
        } else {
            Row(horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                ResourceTile("CPU", "RAM", R.drawable.ic_processor, metrics, "cpu", "ram", Cyan, Modifier.weight(1f))
                ResourceTile("GPU", "VRAM", R.drawable.ic_graphics_card, metrics, "gpu", "vram", Green, Modifier.weight(1f))
            }
        }
    }
}
@OptIn(ExperimentalLayoutApi::class)
@Composable private fun ResourceTile(processor: String, memory: String, @DrawableRes icon: Int, metrics: JSONObject?, prefix: String, memoryPrefix: String, tint: Color, modifier: Modifier=Modifier) {
    val usage=metrics?.number("${prefix}Usage")
    val temperature=metrics?.number("${prefix}Temp")
    val memoryUsage=metrics.ratio("${memoryPrefix}Used", "${memoryPrefix}Total")
    Tile(modifier) {
        Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(6.dp)) {
            DashboardIcon(icon,tint=tint)
            Text(processor,color=tint,fontSize=12.sp,lineHeight=16.sp,fontWeight=FontWeight.Medium)
        }
        FlowRow(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween,itemVerticalAlignment=Alignment.Bottom) {
            Text(usage.percent(),modifier=Modifier.padding(end=8.dp),fontSize=24.sp,lineHeight=32.sp,fontFamily=FontFamily.Monospace,fontWeight=FontWeight.Light)
            Text(temperature?.let { "${String.format(Locale.US,"%.0f",it)}°C" } ?: "—°C",color=Muted,fontSize=12.sp,lineHeight=16.sp,modifier=Modifier.padding(bottom=3.dp).semantics { contentDescription="$processor temperature: ${temperature?.let { "$it degrees Celsius" } ?: "unavailable"}" })
        }
        ResourceBar(usage,tint)
        Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween) {
            Text(memory,color=Muted,fontSize=11.sp,lineHeight=16.sp)
            Text(memoryUsage.percent(),fontFamily=FontFamily.Monospace,fontSize=12.sp,lineHeight=16.sp)
        }
        ResourceBar(memoryUsage,tint.copy(alpha=0.65f))
        Text(metrics.capacity("${memoryPrefix}Used","${memoryPrefix}Total"),color=Muted,fontSize=11.sp,lineHeight=14.sp)
    }
}
@Composable private fun ResourceBar(value: Double?, tint: Color) {
    // A tiny static track keeps missing readings empty; no loading animation.
    Box(Modifier.fillMaxWidth().height(3.dp).clip(RoundedCornerShape(2.dp)).background(Surface)) {
        Box(Modifier.fillMaxWidth(((value ?: 0.0)/100).toFloat().coerceIn(0f,1f)).fillMaxHeight().background(tint))
    }
}
private fun Double?.percent(): String = this?.let { "${it.toInt()}%" } ?: "—"

@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun ModePanel(title: String, service: String, modes: List<Pair<String,String>>, model: DashboardModel, clock: Long) {
    val status=model.service(service,clock)
    val active=status?.optString("mode")
    Tile {
        Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween,verticalAlignment=Alignment.CenterVertically) {
            Text(title,color=Muted,fontSize=11.sp,lineHeight=16.sp,letterSpacing=1.sp)
            Text(modes.firstOrNull { it.first == active }?.second ?: "—",color=Cyan,fontSize=12.sp,lineHeight=16.sp)
        }
        Row(Modifier.fillMaxWidth().selectableGroup(),horizontalArrangement=Arrangement.spacedBy(4.dp)) {
            modes.forEach { (mode,label) ->
                val selected=active == mode
                val enabled=status != null && !model.busy
                Box(Modifier.weight(1f)) {
                    TooltipBox(positionProvider=TooltipDefaults.rememberTooltipPositionProvider(TooltipAnchorPosition.Above),tooltip={PlainTooltip { Text(label) }},state=rememberTooltipState()) {
                        Box(Modifier.fillMaxWidth().heightIn(min=48.dp).clip(RoundedCornerShape(8.dp))
                            .background(if(selected) Cyan.copy(alpha=0.18f) else Surface.copy(alpha=0.45f))
                            .selectable(selected=selected,enabled=enabled,role=Role.RadioButton,onClick={model.action("/v1/$service/$mode")})
                            .semantics { contentDescription=label },contentAlignment=Alignment.Center) {
                            DashboardIcon(modeIcon(service,mode),tint=if(!enabled) Muted.copy(alpha=0.4f) else if(selected) Cyan else Muted)
                        }
                    }
                }
            }
        }
    }
}
@DrawableRes private fun modeIcon(service: String, mode: String): Int = when(service) {
    "rgb" -> when(mode) {
        "night" -> R.drawable.ic_moon
        "day" -> R.drawable.ic_sun
        "off" -> R.drawable.ic_lights_off
        "party" -> R.drawable.ic_party
        else -> R.drawable.ic_aeris_mark
    }
    "cooling" -> when(mode) {
        "quiet" -> R.drawable.ic_wind
        "performance" -> R.drawable.ic_zap
        "firmware" -> R.drawable.ic_chip
        else -> R.drawable.ic_fan
    }
    else -> when(mode) {
        "full" -> R.drawable.ic_monitor
        "system" -> R.drawable.ic_coffee
        else -> R.drawable.ic_moon
    }
}
@Composable private fun Pairing(model: DashboardModel) {
    var url by remember(model.connection) { mutableStateOf(model.connection.url) }
    var token by remember(model.connection) { mutableStateOf(model.connection.token) }
    var relayUrl by remember(model.connection) { mutableStateOf(model.connection.relayUrl) }
    var relayToken by remember(model.connection) { mutableStateOf(model.connection.relayToken) }
    Panel {
        if(model.connectionError.isNotBlank()) Text(model.connectionError,color=MaterialTheme.colorScheme.error,fontSize=12.sp)
        Field("Aeris HTTPS address",url,{url=it},placeholder="https://aeris.your-tailnet.ts.net")
        Field("Aeris pairing token",token,{token=it},secret=true)
        Label("WAKE RELAY · OPTIONAL")
        Field("Wake relay HTTPS address",relayUrl,{relayUrl=it},placeholder="https://casaos.your-tailnet.ts.net")
        Field("Wake relay pairing token",relayToken,{relayToken=it},secret=true)
        Button(onClick={model.save(Connection(url.trim().trimEnd('/'),token.trim(),relayUrl.trim().trimEnd('/'),relayToken.trim()))},enabled=!model.busy,modifier=Modifier.fillMaxWidth()) { Text("Save") }
    }
}
@Composable private fun Field(label: String, value: String, update: (String)->Unit, placeholder: String="", secret: Boolean=false) {
    OutlinedTextField(value=value,onValueChange=update,label={Text(label)},placeholder={Text(placeholder)},singleLine=true,visualTransformation=if(secret) PasswordVisualTransformation() else VisualTransformation.None,modifier=Modifier.fillMaxWidth())
}
private fun JSONObject.number(key: String): Double? = if(has(key) && !isNull(key)) optDouble(key).takeIf { it.isFinite() } else null
private fun JSONObject?.ratio(used: String,total: String): Double? {
    val u=this?.number(used) ?: return null
    val t=number(total)?.takeIf { it>0 } ?: return null
    return 100*u/t
}
private fun JSONObject?.capacity(used: String,total: String, divisor: Double=1073741824.0): String {
    val u=this?.number(used) ?: return "— GiB"
    val t=number(total) ?: return "— GiB"
    return String.format(Locale.US,"%.1f / %.1f GiB",u/divisor,t/divisor)
}
