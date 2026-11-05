package com.touch.tvguide.core

import kotlin.test.*

class MarketsTest {
    private val markets = MarketLogic.parseMarkets(sequenceOf(
        "id,name,state,lat,lon",
        "el-paso-tx,El Paso,TX,31.8,-106.4",
        "omaha-ne,Omaha,NE,41.26,-96.0",
        "lincoln-ne,Lincoln,NE,40.8,-96.7",
        "fort-worth-tx,Fort Worth,TX,32.75,-97.33",
        "dallas-tx,Dallas,TX,32.78,-96.8",
        "kirksville-mo,Kirksville,MO,40.19,-92.58",
        "broken,row",
    ))

    @Test fun parsesMarketsAndSkipsBadRows() {
        assertEquals(6, markets.size)
        assertEquals("El Paso, TX", markets.first().label)
    }

    @Test fun zipHelpers() {
        val zips = MarketLogic.parseZips(sequenceOf("zip,lat,lon", "68102,41.26,-95.94", "x,y,z", "79901,31.76,-106.49"))
        assertEquals(2, zips.size)
        assertEquals("68102", MarketLogic.cleanZip(" 68102-1234 "))
        assertNull(MarketLogic.cleanZip("6810")); assertNull(MarketLogic.cleanZip("abcde"))
        assertEquals("omaha-ne", MarketLogic.marketsForZip("68102", zips, markets).first().id)
        assertEquals("el-paso-tx", MarketLogic.marketsForZip("79901", zips, markets).first().id)
        assertTrue(MarketLogic.marketsForZip("00000", zips, markets).isEmpty())
        assertEquals(2, MarketLogic.marketsForZip("68102", zips, markets, limit = 2).size)
    }

    @Test fun nearestZipForLocation() {
        val zips = MarketLogic.parseZips(sequenceOf("zip,lat,lon", "68102,41.26,-95.94", "79901,31.76,-106.49"))
        assertEquals("79901", MarketLogic.nearestZip(LatLon(31.8, -106.4), zips))
        assertNull(MarketLogic.nearestZip(LatLon(0.0, 0.0), emptyMap()))
    }

    @Test fun channelMarketMatching() {
        fun m(n: String) = MarketLogic.marketOfChannel(n, markets)?.id
        assertEquals("el-paso-tx", m("CBS El Paso"))
        assertEquals("fort-worth-tx", m("US - CBS News Forth Worth"))
        assertEquals("fort-worth-tx", m("US - NBC News Dallas Fortworth"))
        assertEquals("kirksville-mo", m("ABC Kirksvill"))
        assertEquals("dallas-tx", m("ABC Dallas"))
        assertNull(m("COZI TV")); assertNull(m("Court TV"))
        assertNull(m("XOmaha".replace("X", ""))?.let { null }) // exact market name alone is a match, not national
    }

    @Test fun filterKeepsMarketAndNationalChannels() {
        val chs = listOf(
            Channel("1", "CBS El Paso", "4.1", null), Channel("2", "CBS Omaha", "3.1", null), Channel("3", "COZI TV", null, null))
        val progs = chs.map { Program(it.id, "p", null, 1, 2) }
        val f = MarketLogic.filterFor(markets.first(), GuideData(chs, progs), markets)
        assertEquals(listOf("1", "3"), f.channels.map { it.id })
        assertEquals(listOf("1", "3"), f.programs.map { it.channelId })
    }

    @Test fun providersLookup() {
        assertEquals("youtubetv", Providers.byId("youtubetv").id)
        assertEquals("other", Providers.byId("nope").id)
    }
}
