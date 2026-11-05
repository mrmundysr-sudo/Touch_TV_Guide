package com.touch.tvguide.ui

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.zIndex
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.touch.tvguide.R
import com.touch.tvguide.core.*
import java.text.DateFormat
import java.text.SimpleDateFormat
import java.util.*
import kotlin.math.roundToInt

object GridMetrics {
    const val DP_PER_MINUTE = 4f
    const val SLOT_MINUTES = 30
    val CHANNEL_W = 104.dp
    val HEADER_H = 40.dp
    fun rowHeight(fontScale: Float) = (64f * maxOf(1f, fontScale)).dp
}

fun floorSlot(t: Long): Long = t - Math.floorMod(t, GridMetrics.SLOT_MINUTES * 60_000L)
fun ceilSlot(t: Long): Long = floorSlot(t + GridMetrics.SLOT_MINUTES * 60_000L - 1)

/** The visible range: from at most 3 h before now (never before the data begins) to the end of the data. */
data class GridRange(val start: Long, val end: Long) {
    val minutes get() = (end - start) / 60_000f
    companion object {
        fun of(programs: List<Program>, now: Long): GridRange? {
            if (programs.isEmpty()) return null
            val dataStart = programs.minOf { it.startMillis }
            val dataEnd = GuideLogic.dataEnd(programs)
            val s = floorSlot(maxOf(dataStart, now - 3 * 3_600_000L).coerceAtMost(dataEnd - 1))
            val e = ceilSlot(dataEnd)
            return if (e > s) GridRange(s, e) else null
        }
    }
}

fun timeText(ms: Long): String = DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(ms))
fun dayTimeText(ms: Long): String = SimpleDateFormat("EEE h:mm a", Locale.getDefault()).format(Date(ms))
fun timeRange(p: Program) = "${timeText(p.startMillis)} – ${timeText(p.stopMillis)}"

@Composable
fun GuideGrid(
    channels: List<Channel>, cu: Customization, programsByChannel: Map<String, List<Program>>, range: GridRange, now: Long,
    hScroll: ScrollState, fontScale: Float, reminderKeys: Set<String>,
    onProgram: (Channel, Program) -> Unit, onChannel: (Channel) -> Unit, modifier: Modifier = Modifier,
) {
    val rowH = GridMetrics.rowHeight(fontScale)
    val contentW = (range.minutes * GridMetrics.DP_PER_MINUTE).dp
    val primary = MaterialTheme.colorScheme.primary
    Box(modifier.horizontalScroll(hScroll)) {
        Column(Modifier.width(GridMetrics.CHANNEL_W + contentW).fillMaxHeight()) {
            TimeHeader(range, hScroll)
            LazyColumn(Modifier.weight(1f)) {
                items(channels, key = { it.id }) { ch ->
                    ChannelRow(ch, cu, programsByChannel[ch.id].orEmpty(), range, now, hScroll, rowH, reminderKeys, onProgram, onChannel)
                }
            }
        }
        // "now" marker
        if (now in range.start..range.end) {
            val x = GridMetrics.CHANNEL_W + ((now - range.start) / 60_000f * GridMetrics.DP_PER_MINUTE).dp
            Box(Modifier.offset(x = x).width(2.dp).fillMaxHeight().background(primary.copy(alpha = 0.7f)))
        }
    }
}

@Composable
private fun TimeHeader(range: GridRange, hScroll: ScrollState) {
    Box(Modifier.height(GridMetrics.HEADER_H).fillMaxWidth().background(MaterialTheme.colorScheme.surfaceVariant)) {
        var t = range.start
        val cal = Calendar.getInstance()
        while (t < range.end) {
            val x = GridMetrics.CHANNEL_W + ((t - range.start) / 60_000f * GridMetrics.DP_PER_MINUTE).dp
            cal.timeInMillis = t
            val midnightish = cal.get(Calendar.HOUR_OF_DAY) == 0 && cal.get(Calendar.MINUTE) == 0
            val label = if (t == range.start || midnightish) dayTimeText(t) else timeText(t)
            Text(label, Modifier.offset(x = x + 6.dp).align(Alignment.CenterStart), style = MaterialTheme.typography.labelMedium, maxLines = 1)
            Box(Modifier.offset(x = x).width(1.dp).fillMaxHeight().background(MaterialTheme.colorScheme.outline.copy(alpha = 0.4f)))
            t += GridMetrics.SLOT_MINUTES * 60_000L
        }
        Box(Modifier.pinned(hScroll).width(GridMetrics.CHANNEL_W).fillMaxHeight().background(MaterialTheme.colorScheme.surfaceVariant).zIndex(2f),
            contentAlignment = Alignment.Center) { Text(stringResource(R.string.grid_channel), style = MaterialTheme.typography.labelLarge) }
    }
}

/** Keeps a child at the left edge of the viewport while the grid scrolls horizontally. */
private fun Modifier.pinned(hScroll: ScrollState) = this.layout { m, c ->
    val p = m.measure(c)
    layout(p.width, p.height) { p.place(IntOffset(hScroll.value, 0)) }
}

@Composable
private fun ChannelRow(
    ch: Channel, cu: Customization, programs: List<Program>, range: GridRange, now: Long, hScroll: ScrollState, rowH: androidx.compose.ui.unit.Dp,
    reminderKeys: Set<String>, onProgram: (Channel, Program) -> Unit, onChannel: (Channel) -> Unit,
) {
    val visible = GuideLogic.window(programs, ch.id, range.start, range.end)
    val number = GuideLogic.effectiveNumber(ch, cu)
    Box(Modifier.height(rowH).fillMaxWidth()) {
        if (visible.isEmpty()) {
            Text(stringResource(R.string.no_listings), Modifier.offset(x = GridMetrics.CHANNEL_W + 12.dp).align(Alignment.CenterStart),
                color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium)
        }
        for (p in visible) {
            val s = maxOf(p.startMillis, range.start); val e = minOf(p.stopMillis, range.end)
            val x = GridMetrics.CHANNEL_W + ((s - range.start) / 60_000f * GridMetrics.DP_PER_MINUTE).dp
            val w = ((e - s) / 60_000f * GridMetrics.DP_PER_MINUTE).dp
            val airing = now in p.startMillis until p.stopMillis
            val fav = p.key() in cu.favoritePrograms
            val bell = p.key() in reminderKeys
            val desc = stringResource(R.string.cd_program, p.title, timeRange(p)) + (if (fav) ", " + stringResource(R.string.cd_favorite) else "") + (if (bell) ", " + stringResource(R.string.cd_reminder_set) else "")
            Box(Modifier.offset(x = x).width(w).fillMaxHeight().padding(1.dp).clip(RoundedCornerShape(6.dp))
                .background(if (airing) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.secondaryContainer)
                .clickable { onProgram(ch, p) }.semantics { contentDescription = desc }.padding(horizontal = 8.dp, vertical = 4.dp)) {
                Column {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        if (fav) Icon(Icons.Default.Star, null, Modifier.size(14.dp), tint = MaterialTheme.colorScheme.primary)
                        if (bell) Icon(Icons.Default.Notifications, null, Modifier.size(14.dp))
                        Text(p.title, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodyMedium)
                    }
                    Text(timeRange(p), maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        val fav = ch.id in cu.favoriteChannels
        Row(Modifier.pinned(hScroll).zIndex(2f).width(GridMetrics.CHANNEL_W).fillMaxHeight().background(MaterialTheme.colorScheme.surface)
            .border(0.5.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.3f)).clickable { onChannel(ch) }
            .semantics { contentDescription = "Channel $number, ${ch.name}" + (if (fav) ", favorite" else "") + ". Tap for options." }
            .padding(horizontal = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            if (ch.logoUrl != null) AsyncImage(ch.logoUrl, null, Modifier.size(28.dp).padding(end = 4.dp))
            Column {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(number, fontWeight = FontWeight.Bold, style = MaterialTheme.typography.titleSmall, maxLines = 1)
                    if (fav) Icon(Icons.Default.Star, null, Modifier.size(14.dp).padding(start = 2.dp), tint = MaterialTheme.colorScheme.primary)
                }
                Text(ch.name, style = MaterialTheme.typography.labelSmall, maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
        }
        HorizontalDivider(Modifier.align(Alignment.BottomStart).width(GridMetrics.CHANNEL_W + 2000.dp), thickness = 0.5.dp, color = Color.Gray.copy(alpha = 0.3f))
    }
}
