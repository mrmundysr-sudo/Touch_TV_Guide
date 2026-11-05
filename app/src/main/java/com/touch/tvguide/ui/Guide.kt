package com.touch.tvguide.ui

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.touch.tvguide.R
import com.touch.tvguide.core.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GuideScreen(
    s: UiState, openProgram: Pair<String, Long>?, onOpenHandled: () -> Unit,
    onNav: (Route) -> Unit, onRefresh: () -> Unit, vm: MainViewModel, requestReminder: (Program, String) -> Unit,
) {
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) { while (true) { delay(30_000); now = System.currentTimeMillis() } }

    val range = remember(s.data.programs, now / 600_000) { GridRange.of(s.data.programs, now) }
    val byChannel = remember(s.data.programs) { s.data.programs.groupBy { it.channelId } }
    val hScroll = rememberScrollState()
    val scope = rememberCoroutineScope()
    val density = LocalDensity.current
    val sorted = remember(s.data.channels, s.cu) { GuideLogic.sorted(s.data.channels, s.cu) }

    // filter: null = all, "★" = favorites, else category
    var filter by rememberSaveable { mutableStateOf<String?>(null) }
    val categories = remember(s.data.channels, s.cu) { s.data.channels.mapNotNull { GuideLogic.category(it, s.cu) }.distinctBy { it.lowercase() }.sorted() }
    if (filter != null && filter != "★" && filter !in categories) filter = null
    val shown = remember(sorted, filter, s.cu) {
        when (filter) { null -> sorted; "★" -> GuideLogic.favorites(s.data.channels, s.cu); else -> GuideLogic.byCategory(s.data.channels, s.cu, filter!!) }
    }

    var detail by remember { mutableStateOf<Pair<Channel, Program>?>(null) }
    var channelMenu by remember { mutableStateOf<Channel?>(null) }
    val reminderKeys = remember(s.reminders) { s.reminders.map { it.programKey }.toSet() }

    // Initial position: a little before "now".
    var positioned by remember(range?.start) { mutableStateOf(false) }
    LaunchedEffect(range, positioned) {
        if (range != null && !positioned) {
            val px = with(density) { (((now - 20 * 60_000L) - range.start).coerceAtLeast(0) / 60_000f * GridMetrics.DP_PER_MINUTE).dp.roundToPx() }
            hScroll.scrollTo(px.coerceAtMost(hScroll.maxValue)); positioned = true
        }
    }
    // Opened from a reminder notification.
    LaunchedEffect(openProgram, s.data) {
        val (key, start) = openProgram ?: return@LaunchedEffect
        val p = s.data.programs.firstOrNull { it.key() == key }
        if (p != null && range != null) {
            val ch = s.data.channels.firstOrNull { it.id == p.channelId }
            if (ch != null) detail = ch to p
            hScroll.scrollTo(with(density) { ((start - range.start).coerceAtLeast(0) / 60_000f * GridMetrics.DP_PER_MINUTE).dp.roundToPx() }.coerceAtMost(hScroll.maxValue))
            onOpenHandled()
        } else if (s.data.programs.isNotEmpty()) onOpenHandled()
    }
    fun jump(deltaMs: Long) = scope.launch {
        val px = with(density) { (deltaMs / 60_000f * GridMetrics.DP_PER_MINUTE).dp.roundToPx() }
        hScroll.animateScrollTo((hScroll.value + px).coerceIn(0, hScroll.maxValue))
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Column { Text(stringResource(R.string.app_name), style = MaterialTheme.typography.titleMedium); s.market?.let { Text(it.label + " · " + Providers.byId(s.home?.providerId ?: "").label, style = MaterialTheme.typography.bodySmall) } } },
                actions = {
                    IconButton(onClick = { onNav(Route.Search) }) { Icon(Icons.Default.Search, stringResource(R.string.search)) }
                    IconButton(onClick = onRefresh, enabled = !s.refreshing) { Icon(Icons.Default.Refresh, stringResource(R.string.refresh)) }
                    IconButton(onClick = { onNav(Route.Settings) }) { Icon(Icons.Default.Settings, stringResource(R.string.settings)) }
                })
        },
    ) { pad ->
        Column(Modifier.padding(pad).fillMaxSize()) {
            if (s.refreshing) LinearProgressIndicator(Modifier.fillMaxWidth())
            if (s.data.channels.isNotEmpty()) {
                Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 8.dp, vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(filter == null, { filter = null }, label = { Text(stringResource(R.string.filter_all)) })
                    FilterChip(filter == "★", { filter = "★" }, label = { Text(stringResource(R.string.filter_favorites)) }, leadingIcon = { Icon(Icons.Default.Star, null, Modifier.size(16.dp)) })
                    categories.forEach { c -> FilterChip(filter.equals(c, true), { filter = c }, label = { Text(c) }) }
                }
            }
            s.refreshError?.let { err ->
                if (s.data.channels.isNotEmpty()) Surface(color = MaterialTheme.colorScheme.errorContainer, modifier = Modifier.fillMaxWidth()) {
                    Text(err + " " + stringResource(R.string.showing_saved), Modifier.padding(8.dp), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onErrorContainer)
                }
            }
            when {
                !s.ready -> CenterBox { CircularProgressIndicator() }
                s.data.channels.isEmpty() || range == null -> EmptyState(s, onRefresh)
                else -> {
                    Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        TextButton(onClick = { jump(-3 * 3_600_000L) }, enabled = hScroll.value > 0) { Icon(Icons.Default.KeyboardArrowLeft, null); Text(stringResource(R.string.earlier)) }
                        TextButton(onClick = { scope.launch {
                            val px = with(density) { (((now - 20 * 60_000L) - range.start).coerceAtLeast(0) / 60_000f * GridMetrics.DP_PER_MINUTE).dp.roundToPx() }
                            hScroll.animateScrollTo(px.coerceIn(0, hScroll.maxValue)) } }) { Text(stringResource(R.string.now)) }
                        TextButton(onClick = { jump(3 * 3_600_000L) }, enabled = hScroll.value < hScroll.maxValue) { Text(stringResource(R.string.later)); Icon(Icons.Default.KeyboardArrowRight, null) }
                        Spacer(Modifier.weight(1f))
                        Text(stringResource(R.string.listings_end, dayTimeText(range.end)), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    if (shown.isEmpty()) CenterBox { Text(stringResource(if (filter == "★") R.string.no_favorites else R.string.no_channels_in_filter), Modifier.padding(24.dp)) }
                    else GuideGrid(shown, s.cu, byChannel, range, now, hScroll, s.settings.fontScale, reminderKeys, { c, p -> detail = c to p }, { channelMenu = it }, Modifier.weight(1f))
                }
            }
        }
    }

    detail?.let { (ch, p) ->
        ProgramSheet(ch, p, s.cu, GuideLogic.effectiveNumber(ch, s.cu), p.key() in reminderKeys, now, onDismiss = { detail = null },
            onFavorite = { vm.toggleFavoriteProgram(p) }, onRemind = { requestReminder(p, ch.name) }, onCancelRemind = { vm.cancelReminder(p.key()) })
    }
    channelMenu?.let { ch -> ChannelDialog(ch, s, onDismiss = { channelMenu = null }, vm = vm) }
}

@Composable private fun CenterBox(content: @Composable BoxScope.() -> Unit) = Box(Modifier.fillMaxSize(), Alignment.Center, content = content)

@Composable
private fun EmptyState(s: UiState, onRefresh: () -> Unit) = CenterBox {
    Column(Modifier.padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        when {
            s.refreshing -> { CircularProgressIndicator(); Text(stringResource(R.string.loading_guide, s.market?.label ?: "")) }
            s.refreshError != null -> {
                Icon(Icons.Default.Warning, null, tint = MaterialTheme.colorScheme.error, modifier = Modifier.size(40.dp))
                Text(s.refreshError, style = MaterialTheme.typography.bodyLarge); Text(stringResource(R.string.error_no_saved_guide))
                Button(onClick = onRefresh) { Text(stringResource(R.string.try_again)) }
            }
            else -> { Text(stringResource(R.string.no_guide_yet)); Button(onClick = onRefresh) { Text(stringResource(R.string.download_guide)) } }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProgramSheet(ch: Channel, p: Program, cu: Customization, number: String, hasReminder: Boolean, now: Long,
                 onDismiss: () -> Unit, onFavorite: () -> Unit, onRemind: () -> Unit, onCancelRemind: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.padding(horizontal = 20.dp).padding(bottom = 28.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(p.title, style = MaterialTheme.typography.headlineSmall)
            Text("$number · ${ch.name}", style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary)
            Text("${dayTimeText(p.startMillis)} – ${timeText(p.stopMillis)}  (${(p.stopMillis - p.startMillis) / 60_000} min)")
            if (now in p.startMillis until p.stopMillis) Text(stringResource(R.string.on_now), color = MaterialTheme.colorScheme.primary)
            Text(p.description?.takeIf { it.isNotBlank() } ?: stringResource(R.string.no_description))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(top = 8.dp)) {
                val fav = p.key() in cu.favoritePrograms
                OutlinedButton(onClick = onFavorite) { Icon(if (fav) Icons.Default.Favorite else Icons.Default.FavoriteBorder, null); Spacer(Modifier.width(6.dp)); Text(stringResource(if (fav) R.string.unfavorite else R.string.favorite)) }
                if (hasReminder) Button(onClick = { onCancelRemind() }) { Icon(Icons.Default.Notifications, null); Spacer(Modifier.width(6.dp)); Text(stringResource(R.string.cancel_reminder)) }
                else Button(onClick = onRemind, enabled = ReminderLogic.canRemind(p, now)) { Icon(Icons.Default.Notifications, null); Spacer(Modifier.width(6.dp)); Text(stringResource(R.string.remind_me)) }
            }
            if (!hasReminder && !ReminderLogic.canRemind(p, now)) Text(stringResource(R.string.reminder_past), style = MaterialTheme.typography.bodySmall)
        }
    }
}

@Composable
private fun ChannelDialog(ch: Channel, s: UiState, onDismiss: () -> Unit, vm: MainViewModel) {
    var number by remember { mutableStateOf(GuideLogic.effectiveNumber(ch, s.cu).takeIf { it != UNKNOWN_NUMBER } ?: "") }
    var category by remember { mutableStateOf(GuideLogic.category(ch, s.cu) ?: "") }
    val fav = ch.id in s.cu.favoriteChannels
    val clash = s.data.channels.firstOrNull { it.id != ch.id && number.isNotBlank() && GuideLogic.effectiveNumber(it, s.cu) == number.trim() }
    AlertDialog(onDismissRequest = onDismiss, title = { Text(ch.name) }, text = {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            OutlinedTextField(number, { number = it.filter { c -> c.isDigit() || c == '.' }.take(7) }, singleLine = true, label = { Text(stringResource(R.string.channel_number)) },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                supportingText = { Text(if (clash != null) stringResource(R.string.number_clash, clash.name) else stringResource(R.string.number_hint)) })
            OutlinedTextField(category, { category = it.take(24) }, singleLine = true, label = { Text(stringResource(R.string.category)) },
                supportingText = { Text(stringResource(R.string.category_hint)) })
            TextButton(onClick = { vm.toggleFavoriteChannel(ch.id) }) { Icon(if (fav) Icons.Default.Favorite else Icons.Default.FavoriteBorder, null); Spacer(Modifier.width(6.dp)); Text(stringResource(if (fav) R.string.unfavorite else R.string.favorite)) }
        }
    }, confirmButton = {
        TextButton(onClick = {
            val n = number.trim()
            vm.assignNumber(ch.id, if (n.isEmpty()) UNKNOWN_NUMBER else n)
            vm.setCategory(ch.id, category.takeIf { it.isNotBlank() }); onDismiss()
        }) { Text(stringResource(R.string.save)) }
    }, dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } })
}
