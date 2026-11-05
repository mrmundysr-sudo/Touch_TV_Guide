package com.touch.tvguide

import android.Manifest
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.provider.Settings as AndroidSettings
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import com.touch.tvguide.core.Program
import com.touch.tvguide.ui.*
import com.touch.tvguide.work.EXTRA_PROGRAM_KEY
import com.touch.tvguide.work.EXTRA_START
import com.touch.tvguide.work.Notifications

class MainActivity : ComponentActivity() {
    private val vm: MainViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handle(intent)
        setContent {
            val s by vm.state.collectAsState()
            val route by vm.route.collectAsState()
            val open by vm.openProgram.collectAsState()
            val snack = remember { SnackbarHostState() }
            val ctx = LocalContext.current
            LaunchedEffect(Unit) { vm.messages.collect { snack.showSnackbar(it) } }

            // Notification permission flow for reminders (Android 13+).
            var pending by remember { mutableStateOf<Pair<Program, String>?>(null) }
            var askWhy by remember { mutableStateOf(false) }
            val permLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
                val p = pending; pending = null
                if (granted && p != null) vm.addReminder(p.first, p.second)
                else vm.messages.tryEmit(getString(R.string.notifications_denied))
            }
            val requestReminder: (Program, String) -> Unit = { p, name ->
                if (Notifications.enabled(ctx)) vm.addReminder(p, name)
                else if (Build.VERSION.SDK_INT >= 33 && !Notifications.permissionGranted(ctx)) { pending = p to name; askWhy = true }
                else vm.messages.tryEmit(getString(R.string.notifications_denied))
            }

            TvGuideTheme(s.settings.theme, s.settings.fontScale) {
                Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                    Box(Modifier.fillMaxSize()) {
                        when (route) {
                            null -> androidx.compose.foundation.layout.Box(Modifier.fillMaxSize()) { CircularProgressIndicator(Modifier.align(androidx.compose.ui.Alignment.Center)) }
                            Route.Setup -> SetupScreen(vm.catalog, s.home?.zip ?: "", s.home?.providerId ?: "", s.home?.marketId, canCancel = s.home != null,
                                onCancel = { vm.go(Route.Settings) }, onDone = { z, p, m -> vm.finishSetup(z, p, m) })
                            Route.Guide -> GuideScreen(s, open, { vm.openProgram.value = null }, vm::go, { vm.refresh() }, vm, requestReminder)
                            Route.Search -> { BackHandler { vm.go(Route.Guide) }; SearchScreen(s, { vm.go(Route.Guide) }, requestReminder, vm) }
                            Route.Settings -> { BackHandler { vm.go(Route.Guide) }; SettingsScreen(s, { vm.go(Route.Guide) }, vm::go, vm) }
                            Route.Help -> { BackHandler { vm.go(Route.Settings) }; HelpScreen { vm.go(Route.Settings) } }
                            Route.Reminders -> { BackHandler { vm.go(Route.Settings) }; RemindersScreen(s, { vm.go(Route.Settings) }, vm::cancelReminder) }
                        }
                        SnackbarHost(snack, Modifier.align(androidx.compose.ui.Alignment.BottomCenter))
                    }
                }
                if (askWhy) AlertDialog(onDismissRequest = { askWhy = false; pending = null },
                    title = { Text(stringResource(R.string.notif_why_title)) }, text = { Text(stringResource(R.string.notif_why)) },
                    confirmButton = { TextButton(onClick = { askWhy = false; permLauncher.launch(Manifest.permission.POST_NOTIFICATIONS) }) { Text(stringResource(R.string.continue_)) } },
                    dismissButton = { TextButton(onClick = { askWhy = false; pending = null }) { Text(stringResource(R.string.not_now)) } })
            }
        }
    }

    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); handle(intent) }

    private fun handle(i: Intent?) {
        val key = i?.getStringExtra(EXTRA_PROGRAM_KEY) ?: return
        vm.openProgram.value = key to i.getLongExtra(EXTRA_START, 0L)
        vm.route.value = com.touch.tvguide.ui.Route.Guide
    }
}
