package com.touch.tvguide.data

import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/** Where the guide comes from and how often it is fetched. Everything here is centralized config. */
object FeedConfig {
    /** EPGTalk "US Local" guide: ~140 local markets, ~72 hours of listings, one file. */
    const val DEFAULT_URL = "https://raw.githubusercontent.com/acidjesuz/EPGTalk/master/US_local_guide.xml.gz"
    const val USER_AGENT = "TouchTVGuide/1.0 (Android; personal TV listings app; fetches once a day)"
    const val MAX_DOWNLOAD_BYTES = 80L * 1024 * 1024
    const val RAW_CACHE_FILE = "feed-cache.xml.gz"
    fun isAcceptableUrl(u: String) = u.startsWith("https://") && u.length > 12 && !u.contains(' ')
}

enum class ThemeMode { System, Light, Dark }

data class UserSettings(
    val theme: ThemeMode = ThemeMode.System,
    val fontScale: Float = 1f,
    val leadMinutes: Int = 5,
    val feedUrl: String = FeedConfig.DEFAULT_URL,
)

class Settings(ctx: Context) {
    private val p: SharedPreferences = ctx.applicationContext.getSharedPreferences("settings", Context.MODE_PRIVATE)
    private val _flow = MutableStateFlow(read())
    val flow: StateFlow<UserSettings> = _flow

    private fun read() = UserSettings(
        theme = runCatching { ThemeMode.valueOf(p.getString("theme", "System")!!) }.getOrDefault(ThemeMode.System),
        fontScale = p.getFloat("font", 1f),
        leadMinutes = p.getInt("lead", 5),
        feedUrl = p.getString("feed", null)?.takeIf { FeedConfig.isAcceptableUrl(it) } ?: FeedConfig.DEFAULT_URL,
    )

    val current get() = _flow.value
    fun update(f: (UserSettings) -> UserSettings) {
        val n = f(current)
        p.edit().putString("theme", n.theme.name).putFloat("font", n.fontScale).putInt("lead", n.leadMinutes)
            .putString("feed", n.feedUrl).apply()
        _flow.value = n
    }
}
