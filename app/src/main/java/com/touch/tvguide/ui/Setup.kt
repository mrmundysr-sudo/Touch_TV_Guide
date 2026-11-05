package com.touch.tvguide.ui

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.touch.tvguide.R
import com.touch.tvguide.core.*
import com.touch.tvguide.data.Catalog
import androidx.compose.ui.res.stringResource

/** First-run / change-Home flow: 1 location, 2 market, 3 how you watch, then Done. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SetupScreen(catalog: Catalog, initialZip: String, initialProvider: String, initialMarketId: String?, canCancel: Boolean,
                onCancel: () -> Unit, onDone: (zip: String, providerId: String, market: Market) -> Unit) {
    val ctx = LocalContext()
    var step by remember { mutableIntStateOf(0) }
    var zip by remember { mutableStateOf(initialZip) }
    var zipError by remember { mutableStateOf<String?>(null) }
    var locationNote by remember { mutableStateOf<String?>(null) }
    var market by remember { mutableStateOf(initialMarketId?.let { catalog.market(it) }) }
    var provider by remember { mutableStateOf(initialProvider.ifBlank { "antenna" }) }
    var showAll by remember { mutableStateOf(false) }
    var filter by remember { mutableStateOf("") }
    var showLocationWhy by remember { mutableStateOf(false) }

    val locLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) {
            val loc = lastKnown(ctx)
            val z = loc?.let { MarketLogic.nearestZip(LatLon(it.latitude, it.longitude), catalog.zips) }
            if (z != null) { zip = z; zipError = null; locationNote = ctx.getString(R.string.setup_location_found, z) }
            else locationNote = ctx.getString(R.string.setup_location_none)
        } else locationNote = ctx.getString(R.string.setup_location_denied)
    }

    BackHandler(enabled = step > 0 || canCancel) { if (step > 0) step-- else onCancel() }

    Scaffold(topBar = { TopAppBar(title = { Text(stringResource(R.string.setup_title)) }, navigationIcon = {
        if (canCancel && step == 0) TextButton(onClick = onCancel) { Text(stringResource(R.string.cancel)) } }) }) { pad ->
        Column(Modifier.padding(pad).padding(horizontal = 16.dp).fillMaxSize()) {
            Text(stringResource(R.string.setup_step, step + 1, 3), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
            Spacer(Modifier.height(8.dp))
            when (step) {
                0 -> Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(stringResource(R.string.setup_zip_head), style = MaterialTheme.typography.headlineSmall)
                    Text(stringResource(R.string.setup_zip_body))
                    OutlinedTextField(zip, { zip = it.filter { c -> c.isDigit() || c == '-' }.take(10); zipError = null },
                        label = { Text(stringResource(R.string.setup_zip_label)) }, singleLine = true, isError = zipError != null,
                        supportingText = { zipError?.let { Text(it) } },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword), modifier = Modifier.fillMaxWidth())
                    OutlinedButton(onClick = { showLocationWhy = true }, Modifier.fillMaxWidth()) { Text(stringResource(R.string.setup_use_location)) }
                    locationNote?.let { Text(it, style = MaterialTheme.typography.bodyMedium) }
                }
                1 -> Column(Modifier.weight(1f)) {
                    val suggestions = remember(zip) { MarketLogic.marketsForZip(zip, catalog.zips, catalog.markets, 5) }
                    Text(stringResource(R.string.setup_market_head), style = MaterialTheme.typography.headlineSmall)
                    Text(stringResource(R.string.setup_market_body), Modifier.padding(vertical = 8.dp))
                    val list = if (showAll) catalog.markets.filter { filter.isBlank() || it.label.contains(filter, true) } else suggestions
                    if (showAll) OutlinedTextField(filter, { filter = it }, label = { Text(stringResource(R.string.setup_market_filter)) }, singleLine = true, modifier = Modifier.fillMaxWidth())
                    if (!showAll && suggestions.isEmpty()) Text(stringResource(R.string.setup_zip_unknown), color = MaterialTheme.colorScheme.error)
                    LazyColumn(Modifier.weight(1f)) {
                        items(list, key = { it.id }) { m ->
                            Row(Modifier.fillMaxWidth().heightIn(min = 52.dp).selectable(market?.id == m.id, role = Role.RadioButton, onClick = { market = m }),
                                verticalAlignment = Alignment.CenterVertically) {
                                RadioButton(market?.id == m.id, null); Spacer(Modifier.width(12.dp)); Text(m.label)
                            }
                        }
                    }
                    TextButton(onClick = { showAll = !showAll }) { Text(stringResource(if (showAll) R.string.setup_nearest else R.string.setup_all_markets)) }
                }
                else -> Column(Modifier.weight(1f)) {
                    Text(stringResource(R.string.setup_provider_head), style = MaterialTheme.typography.headlineSmall)
                    Text(stringResource(R.string.setup_provider_body), Modifier.padding(vertical = 8.dp))
                    LazyColumn(Modifier.weight(1f)) {
                        items(Providers.all, key = { it.id }) { p ->
                            Row(Modifier.fillMaxWidth().heightIn(min = 56.dp).selectable(provider == p.id, role = Role.RadioButton, onClick = { provider = p.id }),
                                verticalAlignment = Alignment.CenterVertically) {
                                RadioButton(provider == p.id, null); Spacer(Modifier.width(12.dp))
                                Column { Text(p.label); Text(p.note, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                            }
                        }
                    }
                }
            }
            Row(Modifier.fillMaxWidth().padding(vertical = 12.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                if (step > 0) OutlinedButton(onClick = { step-- }) { Text(stringResource(R.string.back)) } else Spacer(Modifier.width(1.dp))
                Button(enabled = step != 1 || market != null, onClick = {
                    when (step) {
                        0 -> {
                            val z = MarketLogic.cleanZip(zip)
                            if (z == null) zipError = ctx.getString(R.string.setup_zip_invalid)
                            else {
                                zip = z
                                val s = MarketLogic.marketsForZip(z, catalog.zips, catalog.markets, 5)
                                if (market == null || market?.id !in s.map { it.id }) market = s.firstOrNull() ?: market
                                step = 1
                            }
                        }
                        1 -> step = 2
                        else -> market?.let { onDone(MarketLogic.cleanZip(zip) ?: zip, provider, it) }
                    }
                }) { Text(stringResource(if (step == 2) R.string.setup_finish else R.string.next)) }
            }
        }
    }

    if (showLocationWhy) AlertDialog(
        onDismissRequest = { showLocationWhy = false },
        title = { Text(stringResource(R.string.setup_location_why_title)) },
        text = { Text(stringResource(R.string.setup_location_why)) },
        confirmButton = { TextButton(onClick = { showLocationWhy = false; locLauncher.launch(Manifest.permission.ACCESS_COARSE_LOCATION) }) { Text(stringResource(R.string.continue_)) } },
        dismissButton = { TextButton(onClick = { showLocationWhy = false }) { Text(stringResource(R.string.not_now)) } })
}

@Composable private fun LocalContext(): Context = androidx.compose.ui.platform.LocalContext.current

/** Last location the OS already knows. Nothing is requested from the network and nothing is stored. */
@SuppressLint("MissingPermission")
private fun lastKnown(ctx: Context): Location? {
    if (ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) return null
    val lm = ctx.getSystemService(Context.LOCATION_SERVICE) as LocationManager
    return lm.getProviders(true).mapNotNull { runCatching { lm.getLastKnownLocation(it) }.getOrNull() }.maxByOrNull { it.time }
}
