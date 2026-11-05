import XCTest
@testable import TVGuideCore

final class GuideLogicTests: XCTestCase {
    let a = Channel(id: "a", name: "KABC", feedNumber: "4.1")
    let b = Channel(id: "b", name: "ESPN")
    let c = Channel(id: "c", name: "CBS", feedNumber: "2")
    var all: [Channel] { [a, b, c] }

    func testUnknownNumbersSortLast() {
        XCTAssertEqual(GuideLogic.sorted(all, Customization()).map(\.id), ["c", "a", "b"])   // 2, 4.1, ?
    }

    func testNumberConflictBecomesQuestionMark() {
        let cu = GuideLogic.assignNumber(all, Customization(), channelId: "b", number: "2")
        XCTAssertEqual(GuideLogic.effectiveNumber(b, cu), "2")
        XCTAssertEqual(GuideLogic.effectiveNumber(c, cu), "?")
        XCTAssertEqual(GuideLogic.sorted(all, cu).map(\.id), ["b", "a", "c"])
        let again = GuideLogic.assignNumber(all, cu, channelId: "c", number: "9")      // "?" channel can be reassigned
        XCTAssertEqual(GuideLogic.effectiveNumber(c, again), "9")
    }

    func testDuplicateDetectionFlagsLegitimateCollisions() {
        let pix = Channel(id: "pix", name: "PIX 11", feedNumber: "11.1")
        let abc = Channel(id: "abc", name: "US - ABC News Raleigh-Durham", feedNumber: "11.1")
        let ch = [pix, abc, a]
        let dups = GuideLogic.duplicateNumbers(ch, Customization())
        XCTAssertEqual(dups.keys.sorted(), ["11.1"]); XCTAssertEqual(dups["11.1"]?.count, 2)
        // The user resolves it by editing a number; the other channel is NOT silently changed.
        let fixed = GuideLogic.assignNumber(ch, Customization(), channelId: "abc", number: "11.2")
        XCTAssertTrue(GuideLogic.duplicateNumbers(ch, fixed).isEmpty)
        XCTAssertEqual(GuideLogic.effectiveNumber(pix, fixed), "11.1")
        // "?" is never a duplicate
        XCTAssertTrue(GuideLogic.duplicateNumbers([b, Channel(id: "z", name: "Z")], Customization()).isEmpty)
    }

    func testCategoriesAndFavorites() {
        var cu = Customization(categories: ["a": "News"])
        XCTAssertEqual(GuideLogic.byCategory(all, cu, category: "news").map(\.id), ["a"])
        cu = GuideLogic.toggleFavoriteChannel(cu, "b"); cu = GuideLogic.toggleFavoriteChannel(cu, "c")
        XCTAssertEqual(GuideLogic.favorites(all, cu).map(\.id), ["c", "b"])
        cu = GuideLogic.toggleFavoriteChannel(cu, "b")
        XCTAssertEqual(cu.favoriteChannels, ["c"])
        let p = Program(channelId: "a", title: "T", description: nil, startMillis: 1, stopMillis: 2)
        cu = GuideLogic.toggleFavoriteProgram(cu, p); XCTAssertTrue(cu.favoritePrograms.contains("a|1"))
        cu = GuideLogic.toggleFavoriteProgram(cu, p); XCTAssertTrue(cu.favoritePrograms.isEmpty)
    }

    func testResetKeepsFavoritesAndRestoresDefaults() {
        var cu = GuideLogic.assignNumber(all, Customization(), channelId: "b", number: "50")
        cu = GuideLogic.setOrder(cu, ids: ["b", "a", "c"]); cu.categories["a"] = "News"; cu = GuideLogic.toggleFavoriteChannel(cu, "a")
        let r = GuideLogic.resetCustomization(cu)
        XCTAssertTrue(r.numbers.isEmpty && r.categories.isEmpty && r.customOrder.isEmpty)
        XCTAssertEqual(r.favoriteChannels, ["a"])
        XCTAssertEqual(GuideLogic.sorted(all, r).map(\.id), ["c", "a", "b"])
    }

    func testCustomOrderThenRest() {
        let cu = GuideLogic.setOrder(Customization(), ids: ["b", "c", "b", "gone"])
        XCTAssertEqual(cu.customOrder, ["b", "c", "gone"])                       // de-duplicated
        XCTAssertEqual(GuideLogic.sorted(all, cu).map(\.id), ["b", "c", "a"])     // unlisted channels follow, by number
    }

    func testWindowAndDataEnd() {
        let p1 = Program(channelId: "a", title: "1", description: nil, startMillis: 0, stopMillis: 100)
        let p2 = Program(channelId: "a", title: "2", description: nil, startMillis: 100, stopMillis: 200)
        let p3 = Program(channelId: "b", title: "3", description: nil, startMillis: 0, stopMillis: 500)
        XCTAssertEqual(GuideLogic.window([p2, p1, p3], channelId: "a", from: 50, to: 150).map(\.title), ["1", "2"])
        XCTAssertTrue(GuideLogic.window([p1], channelId: "a", from: 100, to: 200).isEmpty)       // "No listings"
        XCTAssertEqual(GuideLogic.dataEnd([p1, p2, p3]), 500); XCTAssertEqual(GuideLogic.dataEnd([]), 0)
    }

    func testSearch() {
        let d = GuideData(channels: all, programs: [
            Program(channelId: "c", title: "Evening News", description: nil, startMillis: 1, stopMillis: 2),
            Program(channelId: "a", title: "Cooking", description: "news segment", startMillis: 1, stopMillis: 2)])
        let r = GuideLogic.search(d, Customization(), query: " NEWS ")
        XCTAssertEqual(r.programs.map(\.channelId), ["c", "a"])                    // channel-number order
        XCTAssertEqual(GuideLogic.search(d, Customization(), query: "4.1").channels.map(\.id), ["a"])
        XCTAssertTrue(GuideLogic.search(d, Customization(), query: "  ").channels.isEmpty)
    }

    func testCustomizationDecodesOlderFiles() throws {
        let json = Data(#"{"numbers":{"a":"5"},"favoriteChannels":["a"]}"#.utf8)
        let cu = try JSONDecoder().decode(Customization.self, from: json)
        XCTAssertEqual(cu.numbers["a"], "5"); XCTAssertTrue(cu.customOrder.isEmpty); XCTAssertEqual(cu.favoriteChannels, ["a"])
    }
}
