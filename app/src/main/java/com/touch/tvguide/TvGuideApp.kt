package com.touch.tvguide

import android.app.Application
import com.touch.tvguide.data.*
import com.touch.tvguide.work.AndroidReminderAlarms
import com.touch.tvguide.work.Notifications
import com.touch.tvguide.work.RefreshWorker
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class TvGuideApp : Application() {
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    val settings by lazy { Settings(this) }
    val catalog by lazy { Catalog(this) }
    val repo by lazy {
        GuideRepository(AppDb.open(this), catalog, settings, OkHttpFeedSource(), cacheDir, AndroidReminderAlarms(this))
    }

    override fun onCreate() {
        super.onCreate()
        Notifications.ensureChannel(this)
        RefreshWorker.schedule(this)
        scope.launch { repo.rescheduleAll() }
    }
}
