package com.touch.tvguide.core

/** Feed data. Never modified by user customization. */
data class Channel(val id: String, val name: String, val feedNumber: String?, val logoUrl: String?, val feedCategory: String? = null)

data class Program(
    val channelId: String,
    val title: String,
    val description: String?,
    val startMillis: Long,
    val stopMillis: Long,
)

data class GuideData(val channels: List<Channel>, val programs: List<Program>)

/** User data, stored separately from feed data so a refresh never overwrites it. */
data class Customization(
    val numbers: Map<String, String> = emptyMap(),     // channelId -> user number ("?" allowed)
    val categories: Map<String, String> = emptyMap(),  // channelId -> user category
    val favoriteChannels: Set<String> = emptySet(),
    val favoritePrograms: Set<String> = emptySet(),    // programKey()
)

/** Home profile: exactly one is kept. Provider/location are what the setup screen restores. */
data class HomeProfile(val zip: String, val providerId: String, val customization: Customization)

const val UNKNOWN_NUMBER = "?"

fun Program.key() = "$channelId|$startMillis"
