package com.touch.tvguide.work

import android.content.Context
import androidx.work.*
import com.touch.tvguide.TvGuideApp
import com.touch.tvguide.data.RefreshResult
import java.util.concurrent.TimeUnit

/** Daily background refresh. The repository itself refuses to download more than once per 24 h. */
class RefreshWorker(ctx: Context, params: WorkerParameters) : CoroutineWorker(ctx, params) {
    override suspend fun doWork(): Result {
        val repo = (applicationContext as TvGuideApp).repo
        return when (val r = repo.refresh()) {
            is RefreshResult.Failed -> if (runAttemptCount < 3) Result.retry() else Result.success()
            else -> { repo.rescheduleAll(); Result.success() }
        }
    }

    companion object {
        private const val NAME = "daily-refresh"
        fun schedule(ctx: Context) {
            val req = PeriodicWorkRequestBuilder<RefreshWorker>(24, TimeUnit.HOURS)
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.MINUTES).build()
            WorkManager.getInstance(ctx).enqueueUniquePeriodicWork(NAME, ExistingPeriodicWorkPolicy.KEEP, req)
        }
    }
}
