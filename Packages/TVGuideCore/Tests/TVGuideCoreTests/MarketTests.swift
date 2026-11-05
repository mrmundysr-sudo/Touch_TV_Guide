import XCTest
@testable import TVGuideCore

final class MarketTests: XCTestCase {
    func testParsingSkipsBadRows() {
        XCTAssertEqual(testMarkets.count, 6); XCTAssertEqual(testMarkets.first?.label, "El Paso, TX")
        XCTAssertEqual(testZips.count, 2)
    }

    func testZipRules() {
        XCTAssertEqual(MarketLogic.cleanZip(" 68102-1234 "), "68102")
        XCTAssertNil(MarketLogic.cleanZip("6810")); XCTAssertNil(MarketLogic.cleanZip("abcde")); XCTAssertNil(MarketLogic.cleanZip(""))
        XCTAssertEqual(MarketLogic.marketsForZip("68102", zips: testZips, markets: testMarkets).first?.id, "omaha-ne")
        XCTAssertEqual(MarketLogic.marketsForZip("79901", zips: testZips, markets: testMarkets).first?.id, "el-paso-tx")
        XCTAssertTrue(MarketLogic.marketsForZip("00000", zips: testZips, markets: testMarkets).isEmpty)
        XCTAssertEqual(MarketLogic.marketsForZip("68102", zips: testZips, markets: testMarkets, limit: 2).count, 2)
        XCTAssertEqual(MarketLogic.nearestZip(LatLon(lat: 31.8, lon: -106.4), zips: testZips), "79901")
        XCTAssertNil(MarketLogic.nearestZip(LatLon(lat: 0, lon: 0), zips: [:]))
    }

    func testChannelMarketMatching() {
        func m(_ n: String) -> String? { MarketLogic.marketOfChannel(n, markets: testMarkets)?.id }
        XCTAssertEqual(m("CBS El Paso"), "el-paso-tx")
        XCTAssertEqual(m("US - CBS News Forth Worth"), "fort-worth-tx")
        XCTAssertEqual(m("US - NBC News Dallas Fortworth"), "fort-worth-tx")
        XCTAssertEqual(m("ABC Kirksvill"), "kirksville-mo")
        XCTAssertEqual(m("ABC Dallas"), "dallas-tx")
        XCTAssertEqual(m("FOX San Francisco."), nil)
        XCTAssertNil(m("COZI TV")); XCTAssertNil(m("Court TV"))
    }

    func testFilterKeepsMarketAndUnassignedChannels() throws {
        let d = try XmltvParser.parse(fixtureData("us_local_sample.xml"))
        let f = MarketLogic.filterFor(testMarkets[0], data: d, markets: testMarkets)
        XCTAssertEqual(Set(f.channels.map(\.name)), ["CBS El Paso", "ABC El Paso", "PIX 11", "US - ABC News Raleigh-Durham", "COZI TV"])
        XCTAssertFalse(f.channels.contains { $0.name == "CBS Omaha" })
        XCTAssertEqual(Set(f.programs.map(\.channelId)).isSubset(of: Set(f.channels.map(\.id))), true)
        // The two 11.1 channels the feed really carries are both present and get flagged, not hidden.
        XCTAssertEqual(GuideLogic.duplicateNumbers(f.channels, Customization())["11.1"]?.count, 2)
    }

    func testProviders() {
        XCTAssertEqual(Providers.byId("youtubetv").id, "youtubetv"); XCTAssertEqual(Providers.byId("nope").id, "other")
    }

    func testBundledCatalogMatchesRealData() throws {
        let c = try Catalog.bundled()
        XCTAssertGreaterThanOrEqual(c.markets.count, 130); XCTAssertGreaterThan(c.zips.count, 30_000)
        func first(_ z: String) -> String? { MarketLogic.marketsForZip(z, zips: c.zips, markets: c.markets).first?.id }
        XCTAssertEqual(first("79901"), "el-paso-tx"); XCTAssertEqual(first("10001"), "new-york-ny")
        XCTAssertEqual(first("60601"), "chicago-il"); XCTAssertEqual(first("90012"), "los-angeles-ca")
    }
}
