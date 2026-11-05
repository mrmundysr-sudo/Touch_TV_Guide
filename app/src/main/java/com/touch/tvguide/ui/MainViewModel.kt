package com.touch.tvguide.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.touch.tvguide.TvGuideApp
import com.touch.tvguide.core.*
import com.touch.tvguide.data.*
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch

enum class Route { Guide, Search, Settings, Help, Reminders, Setup }

data class UiState(
    val ready: Boolean = false,
    val home: HomeE? = null,
    val market: Market? = null,
    val data: GuideData = GuideData(emptyList(), emptyList()),
    val cu: Customization = Customization(),
    val reminders: List<Reminder> = emptyList(),
    val lastFetch: Long = 0,
    val refreshing: Boolean = false,
    val refreshError: String? = null,
    val settings: UserSettings = UserSettings(),
)

class MainViewModel(app: Application) : AndroidViewModel(app) {
    private val tv = app as TvGuideApp
    val repo = tv.repo
    val catalog = tv.catalog
    val settings = tv.settings

    private val refreshing = MutableStateFlow(false)
    private val refreshError = MutableStateFlow<String?>(null)
    /** One-shot messages for the snackbar. */
    val messages = MutableSharedFlow<String>(extraBufferCapacity = 8)

    val route = MutableStateFlow<Route?>(null)
    /** Set when a reminder notification opened the app. */
    val openProgram = MutableStateFlow<Pair<String, Long>?>(null)

    private val core = combine(repo.home, repo.guide, repo.customization, repo.reminders, repo.lastFetch) { h, g, c, r, l ->
        UiState(true, h, h?.let { catalog.market(it.marketId) }, g, c, r, l)
    }
    val state: StateFlow<UiState> = combine(core, refreshing, refreshError, settings.flow) { s, rf, err, st ->
        s.copy(refreshing = rf, refreshError = err, settings = st)
    }.stateIn(viewModelScope, SharingStarted.Eagerly, UiState())

    init {
        viewModelScope.launch {
            val home = repo.loadHome()
            route.value = if (home == null) Route.Setup else Route.Guide
            if (home != null) refresh(silent = true)
        }
    }

    fun go(r: Route) { route.value = r }

    fun refresh(silent: Boolean = false, force: Boolean = false) {
        if (refreshing.value) return
        viewModelScope.launch {
            refreshing.value = true
            val res = repo.refresh(force)
            refreshing.value = false
            when (res) {
                is RefreshResult.Updated -> { refreshError.value = null; if (!silent) messages.tryEmit(if (res.downloaded) "Guide updated." else "Guide is up to date.") }
                is RefreshResult.UpToDate -> { refreshError.value = null; if (!silent) messages.tryEmit("Guide is up to date. It refreshes at most once a day.") }
                is RefreshResult.Failed -> { refreshError.value = res.message; if (!silent || !res.haveSavedGuide) messages.tryEmit(res.message + if (res.haveSavedGuide) " Showing your saved guide." else "") }
                RefreshResult.NoHome -> {}
            }
        }
    }

    fun finishSetup(zip: String, providerId: String, market: Market) {
        viewModelScope.launch {
            repo.saveHome(zip, providerId, market.id)
            route.value = Route.Guide
            refresh(silent = false, force = false)
        }
    }

    fun toggleFavoriteChannel(id: String) = viewModelScope.launch { repo.update { GuideLogic.toggleFavoriteChannel(it, id) } }
    fun toggleFavoriteProgram(p: Program) = viewModelScope.launch { repo.update { GuideLogic.toggleFavoriteProgram(it, p) } }
    fun assignNumber(channelId: String, number: String) = viewModelScope.launch { repo.assignNumber(channelId, number) }
    fun setCategory(channelId: String, category: String?) = viewModelScope.launch {
        repo.update { cu ->
            val m = cu.categories.toMutableMap()
            if (category.isNullOrBlank()) m.remove(channelId) else m[channelId] = category.trim()
            cu.copy(categories = m)
        }
    }
    fun resetCustomization() = viewModelScope.launch { repo.resetCustomization(); messages.tryEmit("Numbers and categories reset. Favorites kept.") }

    fun addReminder(p: Program, channelName: String) = viewModelScope.launch {
        if (repo.addReminder(p, channelName)) messages.tryEmit("Reminder set for ${p.title}.") else messages.tryEmit("That show has already started.")
    }
    fun cancelReminder(key: String) = viewModelScope.launch { repo.cancelReminder(key); messages.tryEmit("Reminder cancelled.") }

    fun updateSettings(f: (UserSettings) -> UserSettings) {
        val before = settings.current
        settings.update(f)
        val after = settings.current
        viewModelScope.launch {
            if (before.leadMinutes != after.leadMinutes) repo.rescheduleAll()
            if (before.feedUrl != after.feedUrl) refresh(force = true)
        }
    }
}
