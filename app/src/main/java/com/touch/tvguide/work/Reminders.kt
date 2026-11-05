package com.touch.tvguide.work

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.touch.tvguide.MainActivity
import com.touch.tvguide.R
import com.touch.tvguide.TvGuideApp
import com.touch.tvguide.core.Reminder
import com.touch.tvguide.data.ReminderAlarms
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

const val EXTRA_PROGRAM_KEY = "programKey"
const val EXTRA_START = "startMillis"
private const val CHANNEL_ID = "reminders"

object Notifications {
    fun ensureChannel(ctx: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val nm = ctx.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CHANNEL_ID, ctx.getString(R.string.reminder_channel), NotificationManager.IMPORTANCE_DEFAULT)
            .apply { description = ctx.getString(R.string.reminder_channel_desc) })
    }

    fun permissionGranted(ctx: Context): Boolean =
        Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(ctx, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    fun enabled(ctx: Context) = permissionGranted(ctx) && NotificationManagerCompat.from(ctx).areNotificationsEnabled()
}

/** Inexact alarms (no SCHEDULE_EXACT_ALARM): a reminder may arrive a little off, never silently skipped by the OS. */
class AndroidReminderAlarms(private val ctx: Context) : ReminderAlarms {
    private val am get() = ctx.getSystemService(AlarmManager::class.java)

    private fun pending(r: Reminder?, key: String): PendingIntent {
        val i = Intent(ctx, ReminderReceiver::class.java).setAction("com.touch.tvguide.REMIND").setData(android.net.Uri.parse("tvguide://reminder/" + android.net.Uri.encode(key)))
        if (r != null) {
            i.putExtra(EXTRA_PROGRAM_KEY, r.programKey).putExtra(EXTRA_START, r.startMillis)
                .putExtra("title", r.title).putExtra("channel", r.channelName)
        }
        return PendingIntent.getBroadcast(ctx, 0, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    override fun schedule(r: Reminder, fireAtMillis: Long) {
        am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fireAtMillis, pending(r, r.programKey))
    }

    override fun cancel(programKey: String) {
        am.cancel(pending(null, programKey))
    }
}

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        val key = intent.getStringExtra(EXTRA_PROGRAM_KEY) ?: return
        val start = intent.getLongExtra(EXTRA_START, 0L)
        val title = intent.getStringExtra("title") ?: return
        val channel = intent.getStringExtra("channel") ?: ""
        if (!Notifications.enabled(ctx)) return
        Notifications.ensureChannel(ctx)
        val open = PendingIntent.getActivity(ctx, key.hashCode(),
            Intent(ctx, MainActivity::class.java).putExtra(EXTRA_PROGRAM_KEY, key).putExtra(EXTRA_START, start)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val text = if (channel.isBlank()) ctx.getString(R.string.reminder_text_nochannel) else ctx.getString(R.string.reminder_text, channel)
        val n = NotificationCompat.Builder(ctx, CHANNEL_ID).setSmallIcon(R.drawable.ic_notification).setContentTitle(title)
            .setContentText(text).setContentIntent(open).setAutoCancel(true).setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setWhen(start).setShowWhen(true).build()
        try { NotificationManagerCompat.from(ctx).notify(key.hashCode(), n) } catch (_: SecurityException) { }
        // Retire the reminder row once it has fired.
        val pendingResult = goAsync()
        CoroutineScope(Dispatchers.IO).launch {
            try { (ctx.applicationContext as TvGuideApp).repo.cancelReminder(key) } finally { pendingResult.finish() }
        }
    }
}

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED && intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        val pendingResult = goAsync()
        CoroutineScope(Dispatchers.IO).launch {
            try { (ctx.applicationContext as TvGuideApp).repo.rescheduleAll() } finally { pendingResult.finish() }
        }
    }
}
