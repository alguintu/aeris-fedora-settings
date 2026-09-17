package dev.aeris.companion

import androidx.annotation.DrawableRes
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.DialogProperties
import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale
import java.util.UUID

internal fun displayedSeconds(remaining: Long, ageMillis: Long, running: Boolean): Long =
    (remaining.coerceAtLeast(0) - if(running) ageMillis.coerceAtLeast(0)/1000 else 0).coerceAtLeast(0)
internal fun validateSetInput(reps: String, right: String, load: String, rir: String, perSide: Boolean): String? = when {
    reps.toIntOrNull() !in 1..500 -> "Enter actual reps (1–500)."
    perSide && right.toIntOrNull() !in 1..500 -> "Enter reps for both sides."
    load.isNotBlank() && (load.toDoubleOrNull()?.let { it.isFinite() && it in 0.0..500.0 } != true) -> "Enter load in kg, or leave it blank."
    rir.isNotBlank() && rir.toIntOrNull() !in 0..10 -> "Reps left must be 0–10, or blank."
    else -> null
}
private fun JSONArray?.objects(): List<JSONObject> = if(this == null) emptyList() else (0 until length()).mapNotNull(::optJSONObject)
private fun JSONObject?.string(key: String): String = this?.optString(key)?.takeUnless { it == "null" }.orEmpty()
private fun JSONObject.blocks() = optJSONObject("plan")?.optJSONArray("blocks").objects()
private fun JSONObject.log(block: JSONObject, set: Int) = optJSONObject("logs")?.optJSONObject("${block.optString("id")}:$set")
private fun JSONObject.completed(block: JSONObject): Boolean = (1..block.optInt("sets")).all { log(block,it).string("status") in listOf("done","skipped") }
private fun JSONObject.progressLabel(): String {
    val total=blocks().sumOf { it.optInt("sets") }
    val logs=blocks().flatMap { b -> (1..b.optInt("sets")).map { log(b,it).string("status") } }
    val skipped=logs.count { it == "skipped" }
    return "${logs.count { it == "done" }}/$total sets" + if(skipped > 0) " · $skipped skipped" else ""
}
private fun JSONObject.target(): String = "${optInt("sets")} × ${optInt("reps_min")}–${optInt("reps_max")}" + if(optBoolean("per_side")) " / side" else ""

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable internal fun PomodoroPanel(model: DashboardModel, clock: Long) {
    val live=model.service("tomat",clock)
    val cached=model.status?.optJSONObject("services")?.optJSONObject("tomat")?.optJSONObject("payload")
    val timer=live ?: cached?.takeIf { it.optBoolean("ok") }
    val enabled=live != null && !model.busy
    val phase=timer.string("phase")
    val idle=phase == "Idle"
    val paused=timer?.optBoolean("paused") == true
    val day=timer?.optJSONObject("workout")
    val queued=!idle && timer.string("selectedId").isNotBlank() && timer.string("selectedId") != timer.string("activeId")
    var picker by rememberSaveable { mutableStateOf(false) }
    var workoutOnly by rememberSaveable { mutableStateOf(false) }
    var switchRoutine by rememberSaveable { mutableStateOf(false) }
    var workout by rememberSaveable { mutableStateOf(false) }
    var reset by rememberSaveable { mutableStateOf(false) }
    var editBlock by rememberSaveable { mutableStateOf("") }
    var editSet by rememberSaveable { mutableIntStateOf(0) }
    var editDay by rememberSaveable { mutableStateOf("") }
    var capturedDay by rememberSaveable { mutableStateOf("") }
    fun edit(block: JSONObject, set: Int) {
        capturedDay=day.toString();editDay=day.string("id");editBlock=block.optString("id");editSet=set
    }
    fun command(action: String, id: String?=null) {
        if(!enabled) return
        model.action("/v1/tomat",body=JSONObject().put("action",action).put("revision",timer.string("revision")).apply { if(id != null) put("id",id) })
    }
    Card(shape=RoundedCornerShape(12.dp),colors=CardDefaults.cardColors(containerColor=MaterialTheme.colorScheme.surfaceVariant,contentColor=MaterialTheme.colorScheme.onSurface),modifier=Modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
            Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically) {
                TextButton(onClick={workoutOnly=false;picker=true},enabled=enabled,contentPadding=PaddingValues(horizontal=0.dp),modifier=Modifier.weight(1f)) {
                    Text(timer.string(if(idle) "selectedName" else "activeName").ifBlank { "Pomodoro" },modifier=Modifier.weight(1f),fontSize=14.sp)
                    PomoIcon(R.drawable.ic_chevron_down,null)
                }
                Text("${timer?.optInt("session",1) ?: 1}/${timer?.optInt("sessions",4) ?: 4}",fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
            }
            FlowRow(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween,itemVerticalAlignment=Alignment.CenterVertically) {
                Column {
                    val seconds=displayedSeconds(timer?.optLong("remaining") ?: 0,model.serviceAgeMillis("tomat",clock),!idle && !paused)
                    Text(if(live == null) "—:—" else String.format(Locale.US,"%02d:%02d",seconds/60,seconds%60),fontSize=32.sp,lineHeight=36.sp,fontFamily=FontFamily.Monospace)
                    Text(if(live == null) "Offline" else if(idle) "Ready" else if(paused) "Paused · ${timer.string("stageLabel")}" else timer.string("stageLabel").ifBlank { phase },fontSize=11.sp,lineHeight=16.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Row(Modifier.width(IntrinsicSize.Max)) {
                    IconButton(onClick={command(if(idle) "start" else if(paused) "resume" else "pause")},enabled=enabled) {
                        PomoIcon(if(idle || paused) R.drawable.ic_play else R.drawable.ic_pause,if(idle) "Start timer" else if(paused) "Resume timer" else "Pause timer")
                    }
                    IconButton(onClick={command("skip")},enabled=enabled && !idle) { PomoIcon(R.drawable.ic_skip_forward,"Skip phase") }
                    IconButton(onClick={reset=true},enabled=enabled && !idle) { PomoIcon(R.drawable.ic_rotate_ccw,"Reset timer") }
                }
            }
            if(queued) {
                Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically) {
                    Text("Next: ${timer.string("selectedName")}",fontSize=12.sp,modifier=Modifier.weight(1f),color=MaterialTheme.colorScheme.primary)
                    TextButton(onClick={switchRoutine=true},enabled=enabled) { Text("Switch now") }
                }
            }
            if(day != null) {
                HorizontalDivider(color=MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha=.2f))
                val block=day.blocks().firstOrNull { !day.completed(it) }
                Row(Modifier.fillMaxWidth().heightIn(min=48.dp).clickable { workout=true },verticalAlignment=Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(block?.optString("exercise") ?: day.optJSONObject("plan").string("name"),fontSize=14.sp,lineHeight=20.sp)
                        Text(if(block != null) "${block.target()} · ${day.progressLabel()}" else day.progressLabel(),fontSize=11.sp,lineHeight=16.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    PomoIcon(R.drawable.ic_chevron_down,"Open workout")
                }
                if(block != null && phase in listOf("Break","LongBreak")) {
                    SetButtons(day,block,enabled) { set -> edit(block,set) }
                }
            } else {
                TextButton(onClick={workoutOnly=true;picker=true},enabled=enabled,contentPadding=PaddingValues(horizontal=0.dp)) { Text("Choose workout") }
            }
            if(timer?.string("workoutError")?.isNotBlank() == true) Text(timer.string("workoutError"),color=MaterialTheme.colorScheme.error,fontSize=12.sp)
        }
    }
    if(switchRoutine && queued) AlertDialog(containerColor=MaterialTheme.colorScheme.surfaceVariant,onDismissRequest={switchRoutine=false},title={Text("Switch to ${timer.string("selectedName")}?",style=MaterialTheme.typography.titleMedium)},text={Text("Ends the current timer. Your logged sets stay saved.")},confirmButton={TextButton(onClick={switchRoutine=false;command("reset")},enabled=enabled){Text("Switch")}},dismissButton={TextButton(onClick={switchRoutine=false}){Text("Cancel")}})
    if(reset) AlertDialog(onDismissRequest={reset=false},title={Text("Reset timer?")},text={Text("Your logged sets stay saved.")},confirmButton={TextButton(onClick={reset=false;command("reset")},enabled=enabled){Text("Reset")}},dismissButton={TextButton(onClick={reset=false}){Text("Cancel")}})
    if(picker) ModalBottomSheet(containerColor=MaterialTheme.colorScheme.surfaceVariant,onDismissRequest={picker=false}) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal=20.dp).padding(bottom=24.dp)) {
            Text(if(workoutOnly) "Workouts" else "Routines",style=MaterialTheme.typography.titleLarge)
            if(!idle) Text("Selected for the next run",fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
            timer?.optJSONArray("templates").objects().filter { !workoutOnly || it.has("workout") }.forEach { template ->
                val id=template.optString("id")
                val label=if(!idle && id == timer.string("activeId")) "Active" else if(id == timer.string("selectedId")) if(idle) "Selected" else "Next" else ""
                ListItem(colors=ListItemDefaults.colors(containerColor=MaterialTheme.colorScheme.surfaceVariant),headlineContent={Text(template.optString("name"))},supportingContent={Text("${template.optInt("work_minutes")} / ${template.optInt("break_minutes")} min · ${template.optInt("sessions")} rounds" + if(template.has("workout")) " · workout" else "")},trailingContent={if(label.isNotBlank()) Text(label,fontSize=12.sp,color=MaterialTheme.colorScheme.primary)},modifier=Modifier.clickable(enabled=enabled){command("select",id);picker=false})
            }
            val errors=timer?.optJSONArray("templateErrors")
            if(errors != null) for(i in 0 until errors.length()) Text(errors.optString(i),fontSize=12.sp,color=MaterialTheme.colorScheme.error)
        }
    }
    if(workout && day != null) ModalBottomSheet(containerColor=MaterialTheme.colorScheme.surfaceVariant,onDismissRequest={workout=false},sheetState=rememberModalBottomSheetState(skipPartiallyExpanded=true)) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal=20.dp).padding(bottom=28.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {
            val plan=day.optJSONObject("plan")
            Text(plan.string("name"),style=MaterialTheme.typography.titleLarge)
            Text("${day.optString("date")} · ${day.progressLabel()}" + if(plan.string("status") == "draft") " · Draft" else "",fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
            var details by rememberSaveable { mutableStateOf(false) }
            TextButton(onClick={details=!details}){Text(if(details) "Hide plan notes" else "Plan notes")}
            if(details) { Text(plan.string("notes"),fontSize=13.sp);Text(plan.string("source"),fontSize=11.sp,color=MaterialTheme.colorScheme.onSurfaceVariant) }
            day.blocks().forEach { block ->
                Text(block.optString("exercise"),style=MaterialTheme.typography.titleMedium)
                Text("${block.target()} · after round ${block.optInt("after_round")} · rest ${block.optInt("rest_seconds")}s+",fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
                if(details) Text(block.optString("notes"),fontSize=12.sp)
                SetButtons(day,block,enabled) { set -> edit(block,set) }
            }
        }
    }
    if(editSet > 0 && capturedDay.isNotBlank()) {
        val selectedDay=if(day.string("id") == editDay) day!! else remember(capturedDay) { JSONObject(capturedDay) }
        val block=selectedDay.blocks().firstOrNull { it.optString("id") == editBlock }
        if(block != null) SetEditor(model,selectedDay,block,editSet,enabled,onDismiss={editSet=0})
    }
}
@Composable private fun PomoIcon(@DrawableRes icon: Int, description: String?) {
    Icon(painterResource(icon),contentDescription=description,modifier=Modifier.size(20.dp))
}
@OptIn(ExperimentalLayoutApi::class)
@Composable private fun SetButtons(day: JSONObject, block: JSONObject, enabled: Boolean, edit: (Int)->Unit) {
    FlowRow(horizontalArrangement=Arrangement.spacedBy(8.dp),verticalArrangement=Arrangement.spacedBy(4.dp)) {
        for(set in 1..block.optInt("sets")) {
            val log=day.log(block,set)
            val status=log.string("status")
            OutlinedButton(onClick={edit(set)},enabled=enabled,contentPadding=PaddingValues(horizontal=12.dp),modifier=Modifier.heightIn(min=48.dp)) {
                Text(when(status) {
                    "done" -> "$set · ${log?.optInt("reps")}" + if(block.optBoolean("per_side")) "/${log?.optInt("right_reps")} reps" else " reps"
                    "skipped" -> "$set · Skipped"
                    else -> "Set $set"
                },color=if(status == "done") MaterialTheme.colorScheme.primary else LocalContentColor.current,fontSize=13.sp)
            }
        }
    }
}

@Composable private fun SetEditor(model: DashboardModel, day: JSONObject, block: JSONObject, set: Int, enabled: Boolean, onDismiss: ()->Unit) {
    val key="${day.optString("id")}:${block.optString("id")}:$set"
    val saved=day.log(block,set)
    var reps by rememberSaveable(key) { mutableStateOf(saved.string("reps")) }
    var right by rememberSaveable(key) { mutableStateOf(saved.string("right_reps")) }
    var load by rememberSaveable(key) { mutableStateOf(saved.string("load_kg").ifBlank { block.string("load_kg") }) }
    var rir by rememberSaveable(key) { mutableStateOf(saved.string("rir")) }
    var revision by rememberSaveable(key) { mutableLongStateOf(day.optLong("revision")) }
    var requestId by rememberSaveable(key) { mutableStateOf(UUID.randomUUID().toString()) }
    var lastPayload by rememberSaveable(key) { mutableStateOf("") }
    var validation by rememberSaveable(key) { mutableStateOf("") }
    LaunchedEffect(key) { model.clearWorkoutError() }
    LaunchedEffect(model.savedSetRequestId) { if(model.savedSetRequestId == requestId) onDismiss() }
    fun submit(status: String) {
        if(!enabled) return
        val error=if(status == "done") validateSetInput(reps,right,load,rir,block.optBoolean("per_side")) else null
        if(error != null) { validation=error;return }
        validation=""
        val result=JSONObject().put("status",status)
            .put("reps",if(status == "done") reps.toInt() else JSONObject.NULL)
            .put("right_reps",if(status == "done" && block.optBoolean("per_side")) right.toInt() else JSONObject.NULL)
            .put("load_kg",if(status == "done") load.toDoubleOrNull() ?: JSONObject.NULL else JSONObject.NULL)
            .put("rir",if(status == "done") rir.toIntOrNull() ?: JSONObject.NULL else JSONObject.NULL)
        val body=JSONObject().put("day_id",day.optString("id")).put("expected_revision",revision).put("block_id",block.optString("id")).put("set",set).put("result",result)
        if(lastPayload.isNotBlank() && lastPayload != body.toString()) requestId=UUID.randomUUID().toString()
        lastPayload=body.toString()
        model.action("/v1/workout/set",body=body.put("request_id",requestId))
    }
    AlertDialog(containerColor=MaterialTheme.colorScheme.surfaceVariant,modifier=Modifier.imePadding(),properties=DialogProperties(decorFitsSystemWindows=false),onDismissRequest={if(!model.busy) onDismiss()},title={Text("${block.optString("exercise")} · $set",style=MaterialTheme.typography.titleMedium)},text={
        Column(Modifier.heightIn(max=420.dp).verticalScroll(rememberScrollState()),verticalArrangement=Arrangement.spacedBy(8.dp)) {
            Text(block.target(),fontSize=13.sp)
            Row(horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                SetField(if(block.optBoolean("per_side")) "Left reps" else "Reps",reps,{reps=it},Modifier.weight(1f),enabled)
                if(block.optBoolean("per_side")) SetField("Right reps",right,{right=it},Modifier.weight(1f),enabled)
            }
            SetField("Load · kg (optional)",load,{load=it},Modifier.fillMaxWidth(),enabled,decimal=true)
            SetField("Reps left (optional)",rir,{rir=it},Modifier.fillMaxWidth(),enabled)
            if(validation.isNotBlank()) Text(validation,color=MaterialTheme.colorScheme.error)
            if(model.workoutError.isNotBlank()) Text(model.workoutError,color=MaterialTheme.colorScheme.error,fontSize=12.sp)
            if(revision != day.optLong("revision") || model.workoutError.isNotBlank()) TextButton(onClick={
                reps=saved.string("reps");right=saved.string("right_reps");load=saved.string("load_kg");rir=saved.string("rir")
                revision=day.optLong("revision");requestId=UUID.randomUUID().toString();lastPayload="";validation="";model.clearWorkoutError()
            },enabled=enabled){Text("Reload saved set")}
            Row {
                TextButton(onClick={submit("skipped")},enabled=enabled){Text("Skip set")}
                if(saved != null) TextButton(onClick={submit("pending")},enabled=enabled){Text("Clear set")}
            }
        }
    },confirmButton={TextButton(onClick={submit("done")},enabled=enabled){Text(if(model.busy) "Saving…" else "Save set")}},dismissButton={TextButton(onClick=onDismiss,enabled=!model.busy){Text("Cancel")}})
}
@Composable private fun SetField(label: String, value: String, change: (String)->Unit, modifier: Modifier, enabled: Boolean, decimal: Boolean=false) {
    OutlinedTextField(value=value,onValueChange={if(it.length <= 8) change(it)},label={Text(label)},singleLine=true,enabled=enabled,keyboardOptions=KeyboardOptions(keyboardType=if(decimal) KeyboardType.Decimal else KeyboardType.Number),modifier=modifier)
}
