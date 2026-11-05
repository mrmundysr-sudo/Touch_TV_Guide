package com.touch.tvguide

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.touch.tvguide.core.*
import com.touch.tvguide.data.*
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okio.Buffer
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.io.File
import java.io.IOException
import java.util.zip.GZIPOutputStream
import kotlin.test.*

@RunWith(RobolectricTestRunner::class)
class RepositoryTest {
    private lateinit var ctx: Context
    private lateinit var db: AppDb
    private lateinit var server: MockWebServer
    private lateinit var cache: File
    private lateinit var settings: Settings
    private lateinit var repo: GuideRepository
    private val alarms = FakeAlarms()
    private var now = 1_800_000_000_000L // fixed clock

    private class FakeAlarms : ReminderAlarms {
        val scheduled = LinkedHashMap<String, Long>()
        override fun schedule(r: Reminder, fireAtMillis: Long) { scheduled[r.programKey] = fireAtMillis }
        override fun cancel(programKey: String) { scheduled.remove(programKey) }
    }

    private val catalog = Catalog { name ->
        when (name) {
            "markets.csv" -> "id,name,state,lat,lon\nel-paso-tx,El Paso,TX,31.8,-106.4\nomaha-ne,Omaha,NE,41.26,-96.0\n".byteInputStream()
            else -> "zip,lat,lon\n79901,31.76,-106.49\n".byteInputStream()
        }
    }

    private fun xmlAt(t: Long, title: String = "Evening News", extraStopMin: Int = 60): String {
        fun ts(ms: Long) = java.text.SimpleDateFormat("yyyyMMddHHmmss Z", java.util.Locale.US).apply { timeZone = java.util.TimeZone.getTimeZone("UTC") }.format(java.util.Date(ms))
        return """<?xml version="1.0"?><tv>
          <channel id="ep1"><display-name>CBS El Paso</display-name><display-name>4.1</display-name></channel>
          <channel id="ep2"><display-name>ABC El Paso</display-name><display-name>7.1</display-name></channel>
          <channel id="om1"><display-name>CBS Omaha</display-name><display-name>3.1</display-name></channel>
          <channel id="nat"><display-name>COZI TV</display-name></channel>
          <programme start="${ts(t)}" stop="${ts(t + extraStopMin * 60_000L)}" channel="ep1"><title>$title</title></programme>
          <programme start="${ts(t + 3_600_000)}" stop="${ts(t + 7_200_000)}" channel="ep1"><title>Movie</title></programme>
          <programme start="${ts(t)}" stop="${ts(t + 3_600_000)}" channel="om1"><title>Omaha Show</title></programme>
        </tv>"""
    }

    private fun gz(s: String) = Buffer().also { b -> GZIPOutputStream(b.outputStream()).use { it.write(s.toByteArray()) } }

    @Before fun setUp() {
        ctx = ApplicationProvider.getApplicationContext()
        db = Room.inMemoryDatabaseBuilder(ctx, AppDb::class.java).allowMainThreadQueries().build()
        server = MockWebServer().also { it.start() }
        cache = File(ctx.cacheDir, "t" + System.nanoTime()).also { it.mkdirs() }
        ctx.getSharedPreferences("settings", Context.MODE_PRIVATE).edit().clear().commit()
        settings = Settings(ctx)
        settings.update { it.copy(feedUrl = server.url("/feed.xml.gz").toString()) }
        repo = GuideRepository(db, catalog, settings, source = LocalHttpSource(), cacheDir = cache, alarms = alarms, clock = { now })
    }
    @After fun tearDown() { server.shutdown(); db.close() }

    /** Same as OkHttpFeedSource but allows the plain-http mock server. */
    private inner class LocalHttpSource : FeedSource {
        override fun download(url: String, into: File) {
            val c = okhttp3.OkHttpClient()
            c.newCall(okhttp3.Request.Builder().url(url).build()).execute().use { r ->
                if (!r.isSuccessful) throw IOException("The guide server answered ${r.code}.")
                into.outputStream().use { o -> r.body!!.byteStream().copyTo(o) }
            }
        }
    }

    private fun setup() = runBlocking { repo.saveHome("79901", "antenna", "el-paso-tx") }
    private fun serveGz(xml: String = xmlAt(now + 600_000)) = server.enqueue(MockResponse().setBody(gz(xml)))

    @Test fun setupThenFetchStoresOnlyHomeMarketChannels() = runBlocking {
        assertNull(repo.loadHome()) // fresh install: no home -> setup shown
        assertEquals(RefreshResult.NoHome, repo.refresh())
        setup(); serveGz()
        val r = repo.refresh()
        assertIs<RefreshResult.Updated>(r)
        val g = repo.guide.first()
        assertEquals(setOf("ep1", "ep2", "nat"), g.channels.map { it.id }.toSet()) // El Paso + national, not Omaha
        assertEquals(2, g.programs.size)
        assertEquals("4.1", g.channels.first { it.id == "ep1" }.feedNumber)
        assertTrue(repo.lastFetchMillis() > 0)
        // GuideLogic works on repository-loaded data
        val sorted = GuideLogic.sorted(g.channels, repo.loadCustomization()).map { it.id }
        assertEquals(listOf("ep1", "ep2", "nat"), sorted)
        assertEquals(g.programs.maxOf { it.stopMillis }, GuideLogic.dataEnd(g.programs))
    }

    @Test fun emptyDatabaseIsACleanNoDataState() = runBlocking {
        assertTrue(repo.guide.first().channels.isEmpty())
        assertEquals(Customization(), repo.loadCustomization())
        assertEquals(0L, repo.lastFetchMillis())
    }

    @Test fun customizationSurvivesRefresh() = runBlocking {
        setup(); serveGz(); repo.refresh()
        repo.assignNumber("ep2", "4.1")           // conflict -> ep1 becomes "?"
        repo.update { GuideLogic.toggleFavoriteChannel(it, "ep2") }
        repo.update { it.copy(categories = mapOf("ep1" to "News")) }
        now += 25 * 3_600_000L; serveGz(xmlAt(now + 600_000, "Next Day News"))
        assertIs<RefreshResult.Updated>(repo.refresh())
        val cu = repo.loadCustomization(); val g = repo.guide.first()
        assertEquals("4.1", GuideLogic.effectiveNumber(g.channels.first { it.id == "ep2" }, cu))
        assertEquals("?", GuideLogic.effectiveNumber(g.channels.first { it.id == "ep1" }, cu))
        assertEquals(setOf("ep2"), cu.favoriteChannels); assertEquals("News", cu.categories["ep1"])
        assertTrue(g.programs.any { it.title == "Next Day News" })
    }

    @Test fun failedFetchKeepsSavedGuideAndCustomization() = runBlocking {
        setup(); serveGz(); repo.refresh()
        repo.update { GuideLogic.toggleFavoriteChannel(it, "ep1") }
        val before = repo.guide.first()
        now += 25 * 3_600_000L
        server.enqueue(MockResponse().setResponseCode(500))
        val r = repo.refresh()
        assertIs<RefreshResult.Failed>(r); assertTrue(r.haveSavedGuide)
        assertEquals(before, repo.guide.first())
        assertEquals(setOf("ep1"), repo.loadCustomization().favoriteChannels)
        // garbage body is also rejected without touching anything
        server.enqueue(MockResponse().setBody("<html>not a guide</html>"))
        assertIs<RefreshResult.Failed>(repo.refresh(forceDownload = true))
        assertEquals(before, repo.guide.first())
    }

    @Test fun failedFirstFetchLeavesEmptyStateAndRetryWorks() = runBlocking {
        setup(); server.enqueue(MockResponse().setResponseCode(503))
        val r = repo.refresh(); assertIs<RefreshResult.Failed>(r); assertFalse(r.haveSavedGuide)
        assertTrue(repo.guide.first().channels.isEmpty())
        serveGz(); assertIs<RefreshResult.Updated>(repo.refresh())
        assertTrue(repo.guide.first().channels.isNotEmpty())
    }

    @Test fun neverDownloadsMoreThanOncePerDay() = runBlocking {
        setup(); serveGz(); repo.refresh()
        assertEquals(1, server.requestCount)
        now += 3_600_000L
        assertIs<RefreshResult.UpToDate>(repo.refresh())
        assertEquals(1, server.requestCount)
        now += 24 * 3_600_000L; serveGz(); repo.refresh()
        assertEquals(2, server.requestCount)
    }

    @Test fun changingMarketReusesCachedFileWithoutRedownloading() = runBlocking {
        setup(); serveGz(); repo.refresh()
        assertTrue(repo.saveHome("68102", "cable", "omaha-ne"))
        val r = repo.refresh(); assertIs<RefreshResult.Updated>(r)
        assertEquals(1, server.requestCount)
        assertEquals(setOf("om1", "nat"), repo.guide.first().channels.map { it.id }.toSet())
    }

    @Test fun changingMarketClearsOldCustomizationButSameMarketKeepsIt() = runBlocking {
        setup(); serveGz(); repo.refresh()
        repo.update { GuideLogic.toggleFavoriteChannel(it, "ep1") }
        assertFalse(repo.saveHome("79901", "hulu", "el-paso-tx"))
        assertEquals(setOf("ep1"), repo.loadCustomization().favoriteChannels)
        repo.saveHome("68102", "hulu", "omaha-ne")
        assertEquals(Customization(), repo.loadCustomization())
        assertEquals("omaha-ne", repo.loadHome()!!.marketId); assertEquals("hulu", repo.loadHome()!!.providerId)
    }

    @Test fun resetClearsNumbersAndCategoriesKeepsFavorites() = runBlocking {
        setup(); serveGz(); repo.refresh()
        repo.assignNumber("ep1", "99"); repo.update { it.copy(categories = mapOf("ep1" to "News")) }
        repo.update { GuideLogic.toggleFavoriteChannel(it, "ep1") }
        repo.resetCustomization()
        val cu = repo.loadCustomization()
        assertTrue(cu.numbers.isEmpty()); assertTrue(cu.categories.isEmpty()); assertEquals(setOf("ep1"), cu.favoriteChannels)
    }

    @Test fun duplicateNumberPersistsAcrossReopen() = runBlocking {
        setup(); serveGz(); repo.refresh()
        repo.assignNumber("ep2", "4.1")
        val reopened = GuideRepository(db, catalog, settings, LocalHttpSource(), cache, alarms) { now }
        val cu = reopened.loadCustomization()
        assertEquals("?", cu.numbers["ep1"]); assertEquals("4.1", cu.numbers["ep2"])
    }

    @Test fun remindersAddCancelRescheduleAndReconcile() = runBlocking {
        setup(); serveGz(); repo.refresh()
        val movie = repo.guide.first().programs.first { it.title == "Movie" }
        assertTrue(repo.addReminder(movie, "CBS El Paso"))
        assertEquals(movie.startMillis - 5 * 60_000L, alarms.scheduled[movie.key()])
        assertEquals(1, repo.reminders.first().size)
        // boot / app start re-arms alarms from the database
        alarms.scheduled.clear(); repo.rescheduleAll()
        assertTrue(movie.key() in alarms.scheduled)
        // lead time change re-arms with the new lead
        settings.update { it.copy(leadMinutes = 15) }; repo.rescheduleAll()
        assertEquals(movie.startMillis - 15 * 60_000L, alarms.scheduled[movie.key()])
        // cancel removes alarm and row
        repo.cancelReminder(movie.key())
        assertTrue(alarms.scheduled.isEmpty()); assertTrue(repo.reminders.first().isEmpty())
        // a show that already started can't get a reminder
        val started = movie.copy(startMillis = now - 1000)
        assertFalse(repo.addReminder(started, "x"))
        // refresh that drops the program also drops the reminder
        repo.addReminder(movie, "CBS El Paso")
        now += 25 * 3_600_000L
        server.enqueue(MockResponse().setBody(gz(xmlAt(now + 600_000, "Other").replace("Movie", "Different"))))
        repo.refresh()
        assertTrue(repo.reminders.first().isEmpty()); assertTrue(alarms.scheduled.isEmpty())
    }

    @Test fun changingFeedUrlForcesFreshDownload() = runBlocking {
        setup(); serveGz(); repo.refresh()
        now += 1000
        val second = MockWebServer().also { it.start() }
        second.enqueue(MockResponse().setBody(gz(xmlAt(now + 600_000, "From New Feed"))))
        settings.update { it.copy(feedUrl = second.url("/x.gz").toString()) }
        assertIs<RefreshResult.Updated>(repo.refresh())
        assertEquals(1, second.requestCount)
        assertTrue(repo.guide.first().programs.any { it.title == "From New Feed" })
        second.shutdown()
    }

    @Test fun settingsRejectNonHttpsFeedFromPrefs() {
        ctx.getSharedPreferences("settings", Context.MODE_PRIVATE).edit().putString("feed", "http://evil.example/x").commit()
        assertEquals(FeedConfig.DEFAULT_URL, Settings(ctx).current.feedUrl)
        assertTrue(FeedConfig.isAcceptableUrl(FeedConfig.DEFAULT_URL)); assertFalse(FeedConfig.isAcceptableUrl("ftp://x"))
    }
}
