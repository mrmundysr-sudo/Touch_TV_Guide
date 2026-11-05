package com.touch.tvguide.core

import kotlin.math.PI
import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

/** A local-TV market that appears in the EPGTalk "US Local" feed. [lat]/[lon] are the city centroid. */
data class Market(val id: String, val name: String, val state: String, val lat: Double, val lon: Double) {
    val label get() = "$name, $state"
}

data class LatLon(val lat: Double, val lon: Double)

/** Pure market / zip rules. Zip -> market is "nearest market", which is a heuristic, not a DMA lookup. */
object MarketLogic {
    /** Parses `id,name,state,lat,lon` rows (first row is a header). Bad rows are skipped. */
    fun parseMarkets(lines: Sequence<String>): List<Market> =
        lines.drop(1).mapNotNull { l ->
            val p = l.trim().split(',')
            if (p.size < 5) return@mapNotNull null
            val lat = p[3].toDoubleOrNull() ?: return@mapNotNull null
            val lon = p[4].toDoubleOrNull() ?: return@mapNotNull null
            Market(p[0], p[1], p[2], lat, lon)
        }.toList()

    /** Parses `zip,lat,lon` rows (first row is a header). */
    fun parseZips(lines: Sequence<String>): Map<String, LatLon> {
        val m = HashMap<String, LatLon>(50_000)
        lines.drop(1).forEach { l ->
            val p = l.trim().split(',')
            if (p.size < 3) return@forEach
            val lat = p[1].toDoubleOrNull() ?: return@forEach
            val lon = p[2].toDoubleOrNull() ?: return@forEach
            m[p[0]] = LatLon(lat, lon)
        }
        return m
    }

    /** A valid US zip is exactly five digits. Returns the cleaned zip (ZIP+4 suffix dropped) or null. */
    fun cleanZip(raw: String): String? {
        val z = raw.trim().substringBefore('-')
        return if (z.length == 5 && z.all { it.isDigit() }) z else null
    }

    fun distanceKm(a: LatLon, b: LatLon): Double {
        val r = 6371.0
        fun rad(d: Double) = d * PI / 180
        val dLat = rad(b.lat - a.lat); val dLon = rad(b.lon - a.lon)
        val h = sin(dLat / 2).pow(2) + cos(rad(a.lat)) * cos(rad(b.lat)) * sin(dLon / 2).pow(2)
        return 2 * r * asin(sqrt(h))
    }

    /** Markets ordered nearest first. */
    fun nearest(point: LatLon, markets: List<Market>, limit: Int = 5): List<Market> =
        markets.sortedBy { distanceKm(point, LatLon(it.lat, it.lon)) }.take(limit)

    /** Nearest markets for a zip, or empty if the zip is unknown. */
    fun marketsForZip(zip: String, zips: Map<String, LatLon>, markets: List<Market>, limit: Int = 5): List<Market> {
        val z = cleanZip(zip) ?: return emptyList()
        val p = zips[z] ?: return emptyList()
        return nearest(p, markets, limit)
    }

    /** The zip whose centroid is closest to [point] (used to turn an approximate location into a zip the user confirms). */
    fun nearestZip(point: LatLon, zips: Map<String, LatLon>): String? =
        zips.minByOrNull { (_, v) -> distanceKm(point, v) }?.key

    // The feed has a few misspelt market names; fold them onto the market list before matching.
    private val ALIASES = listOf("kirksvill" to "kirksville", "alburquerque" to "albuquerque", "forth worth" to "fort worth", "fortworth" to "fort worth")

    private fun norm(s: String): String {
        var n = s.lowercase().trim().trimEnd('.', ' ')
        for ((from, to) in ALIASES) if (n.endsWith(from)) n = n.removeSuffix(from) + to
        return n
    }

    /**
     * Which market a feed channel belongs to, from the market name at the end of its name
     * ("CBS El Paso", "US - NBC News Dallas Fortworth"). Longest market name wins. Null = national / unknown.
     */
    fun marketOfChannel(channelName: String, markets: List<Market>): Market? {
        val n = norm(channelName)
        return markets.filter { m ->
            val mn = m.name.lowercase()
            n == mn || (n.endsWith(mn) && !n[n.length - mn.length - 1].isLetter())
        }.maxByOrNull { it.name.length }
    }

    /**
     * Channels to keep for [market]: those whose name ends with the market, plus channels that name no market at all
     * (national digital networks such as COZI or Court TV that the local feed carries).
     */
    fun channelsFor(market: Market, channels: List<Channel>, markets: List<Market>): List<Channel> =
        channels.filter { c ->
            val m = marketOfChannel(c.name, markets)
            m == null || m.id == market.id
        }

    fun filterFor(market: Market, data: GuideData, markets: List<Market>): GuideData {
        val ch = channelsFor(market, data.channels, markets)
        val ids = ch.map { it.id }.toSet()
        return GuideData(ch, data.programs.filter { it.channelId in ids })
    }
}

/** Streaming / TV sources offered in setup. Labels only: lineups differ per subscriber, so numbers stay editable. */
data class Provider(val id: String, val label: String, val note: String)

object Providers {
    val all = listOf(
        Provider("antenna", "Antenna (over the air)", "Local channel numbers match your antenna."),
        Provider("cable", "Cable or satellite", "Numbers come from the broadcast feed; edit them to match your box."),
        Provider("youtubetv", "YouTube TV", "Local channels shown; use Edit number to match your lineup."),
        Provider("hulu", "Hulu + Live TV", "Local channels shown; use Edit number to match your lineup."),
        Provider("sling", "Sling TV", "Local channels vary by plan; edit numbers as needed."),
        Provider("fubo", "Fubo", "Local channels shown; use Edit number to match your lineup."),
        Provider("directv", "DirecTV Stream", "Local channels shown; use Edit number to match your lineup."),
        Provider("philo", "Philo", "Philo carries few local channels; listings may include channels you can't watch."),
        Provider("other", "Something else", "Listings are for your local market's broadcast channels."),
    )
    fun byId(id: String) = all.firstOrNull { it.id == id } ?: all.last()
}
