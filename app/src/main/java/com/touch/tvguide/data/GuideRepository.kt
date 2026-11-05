package com.touch.tvguide.data

import com.touch.tvguide.core.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File
import java.io.IOException

/** Schedules/cancels the OS alarm for a reminder. Faked in tests. */
interface ReminderAlarms {
    fun schedule(r: Reminder, fireAtMillis: Long)
    fun cancel(programKey: String)
}

sealed interface RefreshResult {
    /** Guide rebuilt from the feed (downloaded now or already cached). */
    data class Updated(val channels: Int, val programs: Int, val downloaded: Boolean) : RefreshResult
    /** Less than 24 h since the last download; saved guide kept. */
    data class UpToDate(val nextAllowedMillis: Long) : RefreshResult
    /** Download or parse failed; everything saved is untouched. */
    data class Failed(val message: String, val haveSavedGuide: Boolean) : RefreshResult
    object NoHome : RefreshResult
}

data class GuideSnapshot(val data: GuideData, val customization: Customization)

class GuideRepository(
    private val db: AppDb,
    private val catalog: Catalog,
    private val settings: Settings,
    private val source: FeedSource,
    private val cacheDir: File,
    private val alarms: ReminderAlarms,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    private val dao = db.dao()
    private val refreshLock = Mutex()
    private val rawFile get() = File(cacheDir, FeedConfig.RAW_CACHE_FILE)

    // ---- reading ---------------------------------------------------------------------------------------------

    val home: Flow<HomeE?> = dao.observeHome()
    val lastFetch: Flow<Long> = dao.observeMeta(META_LAST_FETCH).map { it?.toLongOrNull() ?: 0L }
    val reminders: Flow<List<Reminder>> = dao.observeReminders().map { l -> l.map { it.toCore() } }

    val customization: Flow<Customization> = combine(
        dao.observeNumbers(), dao.observeCategories(), dao.observeFavChannels(), dao.observeFavPrograms(),
    ) { n, c, fc, fp ->
        Customization(n.associate { it.channelId to it.number }, c.associate { it.channelId to it.category },
            fc.map { it.channelId }.toSet(), fp.map { it.programKey }.toSet())
    }

    val guide: Flow<GuideData> = combine(dao.observeChannels(), dao.observePrograms()) { c, p ->
        GuideData(c.map { Channel(it.id, it.name, it.feedNumber, it.logoUrl, it.feedCategory) },
            p.map { Program(it.channelId, it.title, it.description, it.startMillis, it.stopMillis) })
    }

    suspend fun loadCustomization(): Customization = Customization(
        dao.numbers().associate { it.channelId to it.number }, dao.categories().associate { it.channelId to it.category },
        dao.favChannels().map { it.channelId }.toSet(), dao.favPrograms().map { it.programKey }.toSet())

    suspend fun loadHome(): HomeE? = dao.home()
    suspend fun lastFetchMillis(): Long = dao.meta(META_LAST_FETCH)?.toLongOrNull() ?: 0L

    // ---- customization (rules come from GuideLogic; this only persists) -----------------------------------------

    suspend fun saveCustomization(cu: Customization) = dao.replaceCustomization(
        cu.numbers.map { UserNumberE(it.key, it.value) }, cu.categories.map { UserCategoryE(it.key, it.value) },
        cu.favoriteChannels.map { FavChannelE(it) }, cu.favoritePrograms.map { FavProgramE(it) })

    private val customLock = Mutex()
    /** Read-modify-write under a lock so two quick edits can't overwrite each other. */
    suspend fun update(f: (Customization) -> Customization) = customLock.withLock { saveCustomization(f(loadCustomization())) }

    suspend fun assignNumber(channelId: String, number: String) {
        val channels = dao.channels().map { Channel(it.id, it.name, it.feedNumber, it.logoUrl, it.feedCategory) }
        update { GuideLogic.assignNumber(channels, it, channelId, number) }
    }

    suspend fun resetCustomization() = update(GuideLogic::resetCustomization)

    // ---- home / setup ------------------------------------------------------------------------------------------

    /**
     * Saves the Home profile. When the market changes the old market's numbers, categories and favourites no
     * longer apply, so customization is cleared; the same market keeps everything. Returns true if it changed markets.
     */
    suspend fun saveHome(zip: String, providerId: String, marketId: String): Boolean {
        val old = dao.home()
        val changed = old != null && old.marketId != marketId
        dao.putHome(HomeE(1, zip, providerId, marketId))
        if (changed) { saveCustomization(Customization()); clearReminders() }
        return changed
    }

    // ---- refresh -----------------------------------------------------------------------------------------------

    /**
     * Fetch (at most once per 24 h), parse, keep only the Home market's channels, store them. Safe on failure:
     * a failed download or parse never touches the saved guide, customization or reminders.
     */
    suspend fun refresh(forceDownload: Boolean = false): RefreshResult = refreshLock.withLock {
        withContext(Dispatchers.IO) {
            val home = dao.home() ?: return@withContext RefreshResult.NoHome
            val market = catalog.market(home.marketId) ?: return@withContext RefreshResult.Failed("Unknown market.", dao.channels().isNotEmpty())
            val now = clock()
            val last = lastFetchMillis()
            val url = settings.current.feedUrl
            val urlChanged = dao.meta(META_FEED_URL) != url
            val needDownload = FeedPolicy.shouldRefresh(last, now, force = forceDownload || !rawFile.exists() || urlChanged)
            var downloaded = false
            if (needDownload) {
                val tmp = File(cacheDir, FeedConfig.RAW_CACHE_FILE + ".tmp")
                try {
                    cacheDir.mkdirs()
                    source.download(url, tmp)
                    val parsed = parse(tmp)
                    if (parsed.channels.isEmpty() || parsed.programs.isEmpty()) throw IOException("That file doesn't look like a TV guide.")
                    if (!tmp.renameTo(rawFile)) { tmp.copyTo(rawFile, overwrite = true) }
                    dao.putMeta(MetaE(META_LAST_FETCH, now.toString())); dao.putMeta(MetaE(META_FEED_URL, url))
                    downloaded = true
                } catch (e: Exception) {
                    tmp.delete()
                    return@withContext RefreshResult.Failed(friendly(e), dao.channels().isNotEmpty())
                }
            } else if (dao.meta(META_APPLIED) == appliedKey(home, last)) {
                return@withContext RefreshResult.UpToDate(FeedPolicy.nextAllowed(last))
            }
            try {
                val full = parse(rawFile)
                val local = MarketLogic.filterFor(market, full, catalog.markets)
                if (local.channels.isEmpty()) return@withContext RefreshResult.Failed("No channels found for ${market.label} in this guide.", dao.channels().isNotEmpty())
                dao.replaceFeed(
                    local.channels.map { ChannelE(it.id, it.name, it.feedNumber, it.logoUrl, it.feedCategory) },
                    local.programs.map { ProgramE(it.channelId, it.startMillis, it.title, it.description, it.stopMillis) })
                dao.putMeta(MetaE(META_APPLIED, appliedKey(home, dao.meta(META_LAST_FETCH)?.toLongOrNull() ?: last)))
                reconcileReminders(local.programs, now)
                if (downloaded) RefreshResult.Updated(local.channels.size, local.programs.size, true)
                else RefreshResult.Updated(local.channels.size, local.programs.size, false)
            } catch (e: Exception) {
                RefreshResult.Failed(friendly(e), dao.channels().isNotEmpty())
            }
        }
    }

    private fun appliedKey(h: HomeE, last: Long) = "${h.marketId}|$last"
    private fun parse(f: File): GuideData = openFeed(f).use { XmltvParser.parse(it) }
    private fun friendly(e: Exception) = when (e) {
        is java.net.UnknownHostException, is java.net.SocketTimeoutException, is java.net.ConnectException ->
            "Couldn't reach the guide server. Check your connection."
        is IOException -> e.message ?: "The guide couldn't be downloaded."
        else -> "The guide file couldn't be read."
    }

    // ---- reminders ---------------------------------------------------------------------------------------------

    /** Returns false if the program has already started (nothing is set). */
    suspend fun addReminder(p: Program, channelName: String): Boolean {
        val now = clock()
        if (!ReminderLogic.canRemind(p, now)) return false
        val r = ReminderLogic.fromProgram(p, channelName)
        dao.putReminder(r.toEntity())
        alarms.schedule(r, ReminderLogic.fireAt(r, settings.current.leadMinutes))
        return true
    }

    suspend fun cancelReminder(programKey: String) { dao.deleteReminder(programKey); alarms.cancel(programKey) }

    private suspend fun clearReminders() { dao.reminders().forEach { alarms.cancel(it.programKey) }; dao.clearReminders() }

    /** Re-arm every pending reminder (app start, boot, lead-time change). Past ones are dropped. */
    suspend fun rescheduleAll() {
        val now = clock(); val lead = settings.current.leadMinutes
        for (e in dao.reminders()) {
            val r = e.toCore()
            if (r.startMillis <= now) { dao.deleteReminder(r.programKey); alarms.cancel(r.programKey) }
            else alarms.schedule(r, maxOf(ReminderLogic.fireAt(r, lead), now + 1_000))
        }
    }

    private suspend fun reconcileReminders(programs: List<Program>, now: Long) {
        val out = ReminderLogic.reconcile(dao.reminders().map { it.toCore() }, programs, now)
        out.dropped.forEach { dao.deleteReminder(it.programKey); alarms.cancel(it.programKey) }
        out.updated.forEach { r ->
            // key may have changed when the program moved
            dao.reminders().firstOrNull { it.channelId == r.channelId && it.title == r.title && it.programKey != r.programKey && it.startMillis != r.startMillis }
                ?.let { dao.deleteReminder(it.programKey); alarms.cancel(it.programKey) }
            dao.putReminder(r.toEntity())
            alarms.schedule(r, maxOf(ReminderLogic.fireAt(r, settings.current.leadMinutes), now + 1_000))
        }
    }

    suspend fun reminder(programKey: String): Reminder? = dao.reminders().firstOrNull { it.programKey == programKey }?.toCore()

    companion object {
        const val META_LAST_FETCH = "lastFetch"
        const val META_FEED_URL = "feedUrl"
        const val META_APPLIED = "applied"
    }
}

private fun ReminderE.toCore() = Reminder(programKey, channelId, channelName, title, startMillis, stopMillis)
private fun Reminder.toEntity() = ReminderE(programKey, channelId, channelName, title, startMillis, stopMillis)
