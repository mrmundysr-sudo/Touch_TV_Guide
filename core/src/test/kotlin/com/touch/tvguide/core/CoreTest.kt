package com.touch.tvguide.core

import kotlin.test.*

class CoreTest {
    private val xml = """<?xml version="1.0"?><tv>
      <channel id="a"><display-name>4.1</display-name><display-name>KABC</display-name><icon src="http://x/a.png"/></channel>
      <channel id="b"><display-name>ESPN</display-name></channel>
      <channel id="c"><display-name>2</display-name><display-name>CBS</display-name></channel>
      <programme start="20261105180000 +0000" stop="20261105190000 +0000" channel="a"><title>News</title><desc>Local news</desc></programme>
      <programme start="20261105190000 +0000" stop="20261105200000 +0000" channel="a"><title>Game</title></programme>
      <programme start="bad" stop="bad" channel="c"><title>Broken</title></programme>
    </tv>"""
    private val data get() = XmltvParser.parse(xml.byteInputStream())

    @Test fun parsesChannelsAndPrograms() {
        val d = data
        assertEquals(3, d.channels.size)
        val a = d.channels.first { it.id == "a" }
        assertEquals("4.1", a.feedNumber); assertEquals("KABC", a.name); assertEquals("http://x/a.png", a.logoUrl)
        assertNull(d.channels.first { it.id == "b" }.feedNumber)
        assertEquals(2, d.programs.size) // broken one skipped
        assertEquals(3_600_000, d.programs[0].stopMillis - d.programs[0].startMillis)
    }

    @Test fun unknownNumbersSortLast() {
        val order = GuideLogic.sorted(data.channels, Customization()).map { it.id }
        assertEquals(listOf("c", "a", "b"), order)
    }

    @Test fun numberConflictBecomesQuestionMark() {
        val d = data
        val cu = GuideLogic.assignNumber(d.channels, Customization(), "b", "2")
        assertEquals("2", GuideLogic.effectiveNumber(d.channels.first { it.id == "b" }, cu))
        assertEquals("?", GuideLogic.effectiveNumber(d.channels.first { it.id == "c" }, cu))
        assertEquals(listOf("b", "a", "c"), GuideLogic.sorted(d.channels, cu).map { it.id }) // 2, 4.1, ?
    }

    @Test fun questionMarkChannelCanBeReassigned() {
        val d = data
        var cu = GuideLogic.assignNumber(d.channels, Customization(), "b", "2")
        cu = GuideLogic.assignNumber(d.channels, cu, "c", "9")
        assertEquals("9", GuideLogic.effectiveNumber(d.channels.first { it.id == "c" }, cu))
    }

    @Test fun categoryOverridesAndExcludesUnassigned() {
        val ch = listOf(Channel("a", "A", "1", null, "News"), Channel("b", "B", "2", null), Channel("c", "C", "3", null, "News"))
        val cu = Customization(categories = mapOf("c" to "Sports"))
        assertEquals(listOf("a"), GuideLogic.byCategory(ch, cu, "News").map { it.id })
        assertEquals(listOf("c"), GuideLogic.byCategory(ch, cu, "Sports").map { it.id })
    }

    @Test fun favoritesInNumericalOrder() {
        val d = data
        val cu = GuideLogic.toggleFavoriteChannel(GuideLogic.toggleFavoriteChannel(Customization(), "a"), "c")
        assertEquals(listOf("c", "a"), GuideLogic.favorites(d.channels, cu).map { it.id })
        assertTrue(GuideLogic.toggleFavoriteChannel(cu, "a").favoriteChannels.none { it == "a" })
    }

    @Test fun windowAndNoListings() {
        val d = data
        val start = d.programs.first { it.channelId == "a" }.startMillis
        assertEquals(1, GuideLogic.window(d.programs, "a", start + 60_000, start + 120_000).size)
        assertEquals(2, GuideLogic.window(d.programs, "a", start, start + 7_200_000).size)
        assertTrue(GuideLogic.window(d.programs, "b", 0, Long.MAX_VALUE).isEmpty())
        assertEquals(d.programs.maxOf { it.stopMillis }, GuideLogic.dataEnd(d.programs))
    }

    @Test fun homeSaveLoadAndReset() {
        val cu = Customization(numbers = mapOf("a" to "7"), categories = mapOf("a" to "News"), favoriteChannels = setOf("a"))
        val home = GuideLogic.saveHome("90210", "yt", cu)
        assertEquals(cu, GuideLogic.loadHome(home))
        val r = GuideLogic.resetCustomization(cu)
        assertTrue(r.numbers.isEmpty() && r.categories.isEmpty()); assertEquals(setOf("a"), r.favoriteChannels)
    }

    @Test fun searchRespectsCustomNumbers() {
        val d = data
        val cu = GuideLogic.assignNumber(d.channels, Customization(), "b", "99")
        val (ch, pr) = GuideLogic.search(d, cu, "99")
        assertEquals(listOf("b"), ch.map { it.id }); assertTrue(pr.isEmpty())
        assertEquals(1, GuideLogic.search(d, cu, "local news").second.size)
    }
}
