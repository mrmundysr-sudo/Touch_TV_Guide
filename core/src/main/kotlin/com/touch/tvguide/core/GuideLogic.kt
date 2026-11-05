package com.touch.tvguide.core

/** Pure guide rules shared by all UI. Mirrors docs/DATA_MODEL.md. */
object GuideLogic {
    fun effectiveNumber(c: Channel, cu: Customization): String =
        cu.numbers[c.id] ?: c.feedNumber ?: UNKNOWN_NUMBER

    private fun sortKey(n: String): Double = n.toDoubleOrNull() ?: Double.MAX_VALUE

    /** Numeric order; "?" (and anything non-numeric) always last, ties broken by name. */
    fun sorted(channels: List<Channel>, cu: Customization): List<Channel> =
        channels.sortedWith(compareBy<Channel>({ sortKey(effectiveNumber(it, cu)) }, { it.name.lowercase() }))

    /**
     * Assign [number] to [channelId]. If another channel already shows that number it becomes "?".
     * Passing "?" simply unassigns. Returns a new Customization.
     */
    fun assignNumber(channels: List<Channel>, cu: Customization, channelId: String, number: String): Customization {
        val n = number.trim()
        val map = cu.numbers.toMutableMap()
        if (n != UNKNOWN_NUMBER) {
            channels.filter { it.id != channelId && effectiveNumber(it, cu) == n }.forEach { map[it.id] = UNKNOWN_NUMBER }
        }
        map[channelId] = n
        return cu.copy(numbers = map)
    }

    fun category(c: Channel, cu: Customization): String? = cu.categories[c.id] ?: c.feedCategory

    /** User assignment overrides feed tag; unassigned channels are excluded from category filters. */
    fun byCategory(channels: List<Channel>, cu: Customization, category: String): List<Channel> =
        sorted(channels.filter { category(it, cu).equals(category, ignoreCase = true) }, cu)

    fun favorites(channels: List<Channel>, cu: Customization): List<Channel> =
        sorted(channels.filter { it.id in cu.favoriteChannels }, cu)

    fun toggleFavoriteChannel(cu: Customization, id: String) =
        cu.copy(favoriteChannels = if (id in cu.favoriteChannels) cu.favoriteChannels - id else cu.favoriteChannels + id)

    fun toggleFavoriteProgram(cu: Customization, p: Program) =
        cu.copy(favoritePrograms = p.key().let { if (it in cu.favoritePrograms) cu.favoritePrograms - it else cu.favoritePrograms + it })

    /** Programs overlapping [fromMillis, toMillis) for one channel; empty list means show "No listings". */
    fun window(programs: List<Program>, channelId: String, fromMillis: Long, toMillis: Long): List<Program> =
        programs.filter { it.channelId == channelId && it.stopMillis > fromMillis && it.startMillis < toMillis }
            .sortedBy { it.startMillis }

    /** Last data time: the right-arrow limit. */
    fun dataEnd(programs: List<Program>): Long = programs.maxOfOrNull { it.stopMillis } ?: 0

    /** Search channels (name or number) and programs (title/description), ordered by channel number. */
    fun search(data: GuideData, cu: Customization, query: String): Pair<List<Channel>, List<Program>> {
        val q = query.trim().lowercase()
        if (q.isEmpty()) return emptyList<Channel>() to emptyList()
        val order = sorted(data.channels, cu).withIndex().associate { it.value.id to it.index }
        val ch = sorted(data.channels, cu).filter { it.name.lowercase().contains(q) || effectiveNumber(it, cu) == q }
        val pr = data.programs.filter { it.title.lowercase().contains(q) || (it.description?.lowercase()?.contains(q) == true) }
            .sortedWith(compareBy({ order[it.channelId] ?: Int.MAX_VALUE }, { it.startMillis }))
        return ch to pr
    }

    /** Overwrite requires UI confirmation; this is the pure operation. */
    fun saveHome(zip: String, providerId: String, cu: Customization) = HomeProfile(zip, providerId, cu)
    fun loadHome(h: HomeProfile): Customization = h.customization

    /** Home-icon long-press: clear custom numbers and categories (favorites kept). */
    fun resetCustomization(cu: Customization) = cu.copy(numbers = emptyMap(), categories = emptyMap())
}
