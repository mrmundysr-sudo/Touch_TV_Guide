import XCTest
@testable import TVGuideCore

final class ParserTests: XCTestCase {
    func testParsesRealFeedShape() throws {
        let d = try XmltvParser.parse(fixtureData("us_local_sample.xml"))
        XCTAssertEqual(d.channels.count, 6)
        let cbs = d.channels.first { $0.id == "I4.1.43312.gracenote.com" }!
        XCTAssertEqual(cbs.name, "CBS El Paso"); XCTAssertEqual(cbs.feedNumber, "4.1")
        XCTAssertEqual(cbs.logoURL, "https://zpmc.tmsimg.com/h3/NowShowing/43312/s28711_ll_h15_ab.png")
        XCTAssertEqual(d.programs.count, 8)                                   // the "bad" programme is skipped
        XCTAssertEqual(d.programs.first { $0.title == "Late & Show" }?.description, "A talk show & more.")
        XCTAssertNil(d.programs.first { $0.title == "Overnight" }?.description)
    }

    func testTimeZoneHandling() throws {
        let d = try XmltvParser.parse(fixtureData("us_local_sample.xml"))
        let utc = d.programs.first { $0.title == "Late & Show" }!.startMillis
        XCTAssertEqual(utc, 1_793_844_000_000)                               // 2026-11-05T02:00:00Z
        XCTAssertEqual(d.programs.first { $0.title == "Offset Time" }!.startMillis, utc + 5 * 3_600_000)   // -0500
        XCTAssertEqual(d.programs.first { $0.title == "No Offset (UTC)" }!.startMillis, utc)
        XCTAssertEqual(XmltvParser.parseTime("19700101000000 +0000"), 0)
        XCTAssertEqual(XmltvParser.parseTime("garbage"), 0); XCTAssertEqual(XmltvParser.parseTime(nil), 0)
        XCTAssertEqual(XmltvParser.parseTime("20260230250000 +0000"), 0)
    }

    func testMalformedAndTruncatedFailClosed() {
        XCTAssertThrowsError(try XmltvParser.parse(Data("<tv><channel id=\"a\">".utf8)))
        XCTAssertThrowsError(try XmltvParser.parse(Data("not xml at all".utf8)))
        XCTAssertThrowsError(try XmltvParser.parse(Data()))
    }

    func testSortedByChannelThenStart() throws {
        let d = try XmltvParser.parse(fixtureData("us_local_sample.xml"))
        let ep = d.programs.filter { $0.channelId == "I4.1.43312.gracenote.com" }
        XCTAssertEqual(ep.map(\.title), ["Late & Show", "Overnight"])
    }

    #if canImport(Compression)
    func testGzipRoundTrip() throws {
        let xml = try fixtureData("us_local_sample.xml")
        let gz = try Gzip.compress(xml)
        XCTAssertTrue(Gzip.isGzip(gz)); XCTAssertFalse(Gzip.isGzip(xml))
        XCTAssertEqual(try Gzip.decompress(gz), xml)
        XCTAssertEqual(try Gzip.decompressIfNeeded(xml), xml)
        XCTAssertEqual(try XmltvParser.parse(Gzip.decompressIfNeeded(gz)).channels.count, 6)
        XCTAssertThrowsError(try Gzip.decompress(Data([0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 0, 3, 1, 2, 3])))
    }
    #endif
}
