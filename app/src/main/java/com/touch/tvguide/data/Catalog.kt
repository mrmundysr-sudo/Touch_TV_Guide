package com.touch.tvguide.data

import android.content.Context
import com.touch.tvguide.core.LatLon
import com.touch.tvguide.core.Market
import com.touch.tvguide.core.MarketLogic

/** Bundled market list and zip table (assets). Loaded lazily; the zip table is ~40k rows. */
class Catalog(private val open: (String) -> java.io.InputStream) {
    constructor(ctx: Context) : this({ ctx.applicationContext.assets.open(it) })

    val markets: List<Market> by lazy { open("markets.csv").bufferedReader().useLines { MarketLogic.parseMarkets(it) } }
    val zips: Map<String, LatLon> by lazy { open("zips.csv").bufferedReader().useLines { MarketLogic.parseZips(it) } }
    fun market(id: String) = markets.firstOrNull { it.id == id }
}
