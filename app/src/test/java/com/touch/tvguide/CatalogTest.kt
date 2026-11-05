package com.touch.tvguide

import androidx.test.core.app.ApplicationProvider
import com.touch.tvguide.core.MarketLogic
import com.touch.tvguide.data.Catalog
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import kotlin.test.*

/** Checks the real bundled assets, not fixtures. */
@RunWith(RobolectricTestRunner::class)
class CatalogTest {
    private val catalog = Catalog(ApplicationProvider.getApplicationContext<android.content.Context>())

    @Test fun bundledMarketsAndZips() {
        assertTrue(catalog.markets.size >= 130, "markets=${catalog.markets.size}")
        assertTrue(catalog.zips.size > 30_000)
        assertEquals("el-paso-tx", MarketLogic.marketsForZip("79901", catalog.zips, catalog.markets).first().id)
        assertEquals("new-york-ny", MarketLogic.marketsForZip("10001", catalog.zips, catalog.markets).first().id)
        assertEquals("chicago-il", MarketLogic.marketsForZip("60601", catalog.zips, catalog.markets).first().id)
        assertEquals("los-angeles-ca", MarketLogic.marketsForZip("90012", catalog.zips, catalog.markets).first().id)
    }
}
