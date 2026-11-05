package com.touch.tvguide.ui

import android.content.Intent
import android.net.Uri
import android.provider.Settings as AndroidSettings
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.touch.tvguide.BuildConfig
import com.touch.tvguide.R
import com.touch.tvguide.core.*
import com.touch.tvguide.data.*
import com.touch.tvguide.work.Notifications
import java.text.DateFormat
import java.util.Date

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SubScreen(title: String, onBack: () -> Unit, content: @Composable ColumnScope.() -> Unit) {
    Scaffold(topBar = { TopAppBar(title = { Text(title) }, navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.back)) } }) }) { pad ->
        Column(Modifier.padding(pad).fillMaxSize(), content = content)
    }
}

@Composable
fun SearchScreen(s: UiState, onBack: () -> Unit, requestReminder: (Program, String) -> Unit, vm: MainViewModel) {
    var q by rememberSaveable { mutableStateOf("") }
    val result = remember(q, s.data, s.cu) { GuideLogic.search(s.data, s.cu, q) }
    var detail by remember { mutableStateOf<Pair<Channel, Program>?>(null) }
    val now = remember(detail) { System.currentTimeMillis() }
    val byId = remember(s.data.channels) { s.data.channels.associateBy { it.id } }
    SubScreen(stringResource(R.string.search), onBack) {
        OutlinedTextField(q, { q = it }, Modifier.fillMaxWidth().padding(12.dp), singleLine = true, label = { Text(stringResource(R.string.search_hint)) },
            leadingIcon = { Icon(Icons.Default.Search, null) })
        val (chs, progs) = result
        if (q.isBlank()) Text(stringResource(R.string.search_prompt), Modifier.padding(16.dp))
        else if (chs.isEmpty() && progs.isEmpty()) Text(stringResource(R.string.search_none, q.trim()), Modifier.padding(16.dp))
        else LazyColumn(Modifier.weight(1f)) {
            if (chs.isNotEmpty()) item { Text(stringResource(R.string.channels), Modifier.padding(horizontal = 16.dp, vertical = 8.dp), style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary) }
            items(chs, key = { "c" + it.id }) { c ->
                val next = s.data.programs.filter { it.channelId == c.id && it.stopMillis > now }.minByOrNull { it.startMillis }
                ListItem(headlineContent = { Text("${GuideLogic.effectiveNumber(c, s.cu)}  ${c.name}") },
                    supportingContent = { Text(next?.let { stringResource(R.string.on_now_next, it.title, timeText(it.startMillis)) } ?: stringResource(R.string.no_listings)) },
                    modifier = Modifier.clickable(enabled = next != null) { next?.let { detail = c to it } })
            }
            if (progs.isNotEmpty()) item { Text(stringResource(R.string.programs), Modifier.padding(horizontal = 16.dp, vertical = 8.dp), style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary) }
            items(progs.take(200), key = { "p" + it.key() }) { p ->
                val c = byId[p.channelId]
                ListItem(headlineContent = { Text(p.title) },
                    supportingContent = { Text("${c?.let { GuideLogic.effectiveNumber(it, s.cu) } ?: "?"} ${c?.name ?: ""} · ${dayTimeText(p.startMillis)}") },
                    modifier = Modifier.clickable { c?.let { detail = it to p } })
            }
        }
    }
    detail?.let { (ch, p) ->
        val has = s.reminders.any { it.programKey == p.key() }
        ProgramSheet(ch, p, s.cu, GuideLogic.effectiveNumber(ch, s.cu), has, System.currentTimeMillis(), { detail = null },
            { vm.toggleFavoriteProgram(p) }, { requestReminder(p, ch.name) }, { vm.cancelReminder(p.key()) })
    }
}

@Composable
fun RemindersScreen(s: UiState, onBack: () -> Unit, onCancel: (String) -> Unit) {
    val ctx = LocalContext.current
    SubScreen(stringResource(R.string.reminders), onBack) {
        if (!Notifications.enabled(ctx)) Surface(color = MaterialTheme.colorScheme.errorContainer, modifier = Modifier.fillMaxWidth()) {
            Column(Modifier.padding(12.dp)) {
                Text(stringResource(R.string.notifications_off))
                TextButton(onClick = { ctx.startActivity(Intent(AndroidSettings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(AndroidSettings.EXTRA_APP_PACKAGE, ctx.packageName)) }) { Text(stringResource(R.string.open_settings)) }
            }
        }
        if (s.reminders.isEmpty()) Text(stringResource(R.string.no_reminders), Modifier.padding(16.dp))
        LazyColumn { items(s.reminders, key = { it.programKey }) { r ->
            ListItem(headlineContent = { Text(r.title) }, supportingContent = { Text("${r.channelName} · ${dayTimeText(r.startMillis)}") },
                trailingContent = { IconButton(onClick = { onCancel(r.programKey) }) { Icon(Icons.Default.Delete, stringResource(R.string.cancel_reminder_for, r.title)) } })
        } }
    }
}

@Composable
fun SettingsScreen(s: UiState, onBack: () -> Unit, onNav: (Route) -> Unit, vm: MainViewModel) {
    val st = s.settings
    var confirmHome by remember { mutableStateOf(false) }
    var confirmReset by remember { mutableStateOf(false) }
    var feedEdit by remember { mutableStateOf(false) }
    SubScreen(stringResource(R.string.settings), onBack) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
            Section(R.string.sec_guide)
            s.market?.let { ListItem(headlineContent = { Text(it.label) }, supportingContent = { Text(stringResource(R.string.home_summary, s.home?.zip ?: "", Providers.byId(s.home?.providerId ?: "").label)) }) }
            ListItem(headlineContent = { Text(stringResource(R.string.last_updated)) },
                supportingContent = { Text(if (s.lastFetch > 0) DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(s.lastFetch)) else stringResource(R.string.never)) },
                trailingContent = { Button(onClick = { vm.refresh() }, enabled = !s.refreshing) { Text(stringResource(R.string.refresh)) } })
            Text(stringResource(R.string.refresh_note), Modifier.padding(horizontal = 16.dp), style = MaterialTheme.typography.bodySmall)
            ListItem(headlineContent = { Text(stringResource(R.string.change_home)) }, supportingContent = { Text(stringResource(R.string.change_home_sub)) }, modifier = Modifier.clickable { confirmHome = true })
            ListItem(headlineContent = { Text(stringResource(R.string.reset_custom)) }, supportingContent = { Text(stringResource(R.string.reset_custom_sub)) }, modifier = Modifier.clickable { confirmReset = true })
            ListItem(headlineContent = { Text(stringResource(R.string.reminders)) }, supportingContent = { Text(stringResource(R.string.reminders_count, s.reminders.size)) }, modifier = Modifier.clickable { onNav(Route.Reminders) })

            Section(R.string.sec_look)
            Text(stringResource(R.string.theme), Modifier.padding(horizontal = 16.dp), fontWeight = FontWeight.Medium)
            RadioRow(listOf(ThemeMode.System to R.string.theme_system, ThemeMode.Light to R.string.theme_light, ThemeMode.Dark to R.string.theme_dark), st.theme) { m -> vm.updateSettings { it.copy(theme = m) } }
            Text(stringResource(R.string.text_size), Modifier.padding(horizontal = 16.dp, vertical = 4.dp), fontWeight = FontWeight.Medium)
            RadioRow(listOf(0.9f to R.string.size_small, 1f to R.string.size_default, 1.2f to R.string.size_large, 1.4f to R.string.size_xl), st.fontScale) { f -> vm.updateSettings { it.copy(fontScale = f) } }

            Section(R.string.sec_reminders)
            Text(stringResource(R.string.lead_time), Modifier.padding(horizontal = 16.dp), fontWeight = FontWeight.Medium)
            RadioRow(listOf(5 to R.string.lead_5, 10 to R.string.lead_10, 15 to R.string.lead_15, 30 to R.string.lead_30), st.leadMinutes) { m -> vm.updateSettings { it.copy(leadMinutes = m) } }

            Section(R.string.sec_data)
            ListItem(headlineContent = { Text(stringResource(R.string.feed_address)) }, supportingContent = { Text(st.feedUrl) }, modifier = Modifier.clickable { feedEdit = true })

            Section(R.string.sec_about)
            ListItem(headlineContent = { Text(stringResource(R.string.help_title)) }, modifier = Modifier.clickable { onNav(Route.Help) })
            ListItem(headlineContent = { Text(stringResource(R.string.version, BuildConfig.VERSION_NAME)) }, supportingContent = { Text(stringResource(R.string.sources_short)) })
        }
    }
    if (confirmHome) AlertDialog(onDismissRequest = { confirmHome = false }, title = { Text(stringResource(R.string.change_home)) }, text = { Text(stringResource(R.string.change_home_confirm)) },
        confirmButton = { TextButton(onClick = { confirmHome = false; onNav(Route.Setup) }) { Text(stringResource(R.string.continue_)) } },
        dismissButton = { TextButton(onClick = { confirmHome = false }) { Text(stringResource(R.string.cancel)) } })
    if (confirmReset) AlertDialog(onDismissRequest = { confirmReset = false }, title = { Text(stringResource(R.string.reset_custom)) }, text = { Text(stringResource(R.string.reset_confirm)) },
        confirmButton = { TextButton(onClick = { confirmReset = false; vm.resetCustomization() }) { Text(stringResource(R.string.reset)) } },
        dismissButton = { TextButton(onClick = { confirmReset = false }) { Text(stringResource(R.string.cancel)) } })
    if (feedEdit) {
        var url by remember { mutableStateOf(st.feedUrl) }
        val ok = FeedConfig.isAcceptableUrl(url.trim())
        AlertDialog(onDismissRequest = { feedEdit = false }, title = { Text(stringResource(R.string.feed_address)) }, text = {
            Column { Text(stringResource(R.string.feed_note)); OutlinedTextField(url, { url = it }, isError = !ok, modifier = Modifier.fillMaxWidth(), supportingText = { if (!ok) Text(stringResource(R.string.feed_invalid)) }) }
        }, confirmButton = { TextButton(enabled = ok, onClick = { feedEdit = false; vm.updateSettings { it.copy(feedUrl = url.trim()) } }) { Text(stringResource(R.string.save)) } },
            dismissButton = { Row { TextButton(onClick = { url = FeedConfig.DEFAULT_URL }) { Text(stringResource(R.string.use_default)) }; TextButton(onClick = { feedEdit = false }) { Text(stringResource(R.string.cancel)) } } })
    }
}

@Composable private fun Section(res: Int) = Text(stringResource(res), Modifier.padding(start = 16.dp, top = 20.dp, bottom = 4.dp), style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary)

@Composable
private fun <T> RadioRow(options: List<Pair<T, Int>>, selected: T, onSelect: (T) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp)) {
        options.forEach { (v, label) ->
            Row(Modifier.weight(1f).heightIn(min = 48.dp).selectable(v == selected, role = Role.RadioButton, onClick = { onSelect(v) }), verticalAlignment = Alignment.CenterVertically) {
                RadioButton(v == selected, null, Modifier.padding(horizontal = 6.dp)); Text(stringResource(label), style = MaterialTheme.typography.bodyMedium)
            }
        }
    }
}

@Composable
fun HelpScreen(onBack: () -> Unit) {
    SubScreen(stringResource(R.string.help_title), onBack) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            listOf(R.string.help_h_start to R.string.help_b_start, R.string.help_h_grid to R.string.help_b_grid, R.string.help_h_channels to R.string.help_b_channels,
                R.string.help_h_fav to R.string.help_b_fav, R.string.help_h_search to R.string.help_b_search, R.string.help_h_rem to R.string.help_b_rem,
                R.string.help_h_offline to R.string.help_b_offline, R.string.help_h_privacy to R.string.help_b_privacy, R.string.help_h_sources to R.string.help_b_sources,
                R.string.help_h_limits to R.string.help_b_limits).forEach { (h, b) ->
                Text(stringResource(h), style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.primary); Text(stringResource(b))
            }
        }
    }
}
