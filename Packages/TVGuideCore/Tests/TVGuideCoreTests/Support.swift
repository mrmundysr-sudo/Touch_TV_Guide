import Foundation
@testable import TVGuideCore

func fixtureData(_ name: String) throws -> Data {
    let url = Bundle.module.resourceURL!.appendingPathComponent("Fixtures").appendingPathComponent(name)
    return try Data(contentsOf: url)
}

func tempDir() -> URL {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("tvg-" + UUID().uuidString)
    try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

let testMarkets = MarketLogic.parseMarkets("""
id,name,state,lat,lon
el-paso-tx,El Paso,TX,31.8,-106.4
omaha-ne,Omaha,NE,41.26,-96.0
lincoln-ne,Lincoln,NE,40.8,-96.7
fort-worth-tx,Fort Worth,TX,32.75,-97.33
dallas-tx,Dallas,TX,32.78,-96.8
kirksville-mo,Kirksville,MO,40.19,-92.58
broken,row
""")
let testZips = MarketLogic.parseZips("zip,lat,lon\n68102,41.26,-95.94\n79901,31.76,-106.49\nx,y,z\n")
let testCatalog = Catalog(markets: testMarkets, zips: testZips)
