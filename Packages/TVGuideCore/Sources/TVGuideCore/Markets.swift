import Foundation

/// A local-TV market that appears in the EPGTalk "US Local" feed. lat/lon is the city centroid.
public struct Market: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let state: String
    public let lat: Double
    public let lon: Double
    public init(id: String, name: String, state: String, lat: Double, lon: Double) {
        self.id = id; self.name = name; self.state = state; self.lat = lat; self.lon = lon
    }
    public var label: String { "\(name), \(state)" }
}

public struct LatLon: Equatable, Sendable {
    public let lat: Double
    public let lon: Double
    public init(lat: Double, lon: Double) { self.lat = lat; self.lon = lon }
}

/// Bundled market list and zip table. The zip table is ~42k rows; load it off the main thread.
public struct Catalog: Sendable {
    public let markets: [Market]
    public let zips: [String: LatLon]
    public init(markets: [Market], zips: [String: LatLon]) { self.markets = markets; self.zips = zips }
    public func market(id: String) -> Market? { markets.first { $0.id == id } }

    public static func bundled() throws -> Catalog {
        guard let m = Bundle.module.url(forResource: "markets", withExtension: "csv"),
              let z = Bundle.module.url(forResource: "zips", withExtension: "csv") else { throw CocoaError(.fileNoSuchFile) }
        let markets = MarketLogic.parseMarkets(try String(contentsOf: m, encoding: .utf8))
        let zips = MarketLogic.parseZips(try String(contentsOf: z, encoding: .utf8))
        return Catalog(markets: markets, zips: zips)
    }
}

/// Pure market / zip rules. Zip -> market is "nearest market", which is a heuristic, not a DMA lookup.
public enum MarketLogic {
    /// Parses `id,name,state,lat,lon` rows (first row is a header). Bad rows are skipped.
    public static func parseMarkets(_ csv: String) -> [Market] {
        csv.split(whereSeparator: \.isNewline).dropFirst().compactMap { line in
            let p = line.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard p.count >= 5, let lat = Double(p[3]), let lon = Double(p[4]) else { return nil }
            return Market(id: p[0], name: p[1], state: p[2], lat: lat, lon: lon)
        }
    }

    /// Parses `zip,lat,lon` rows (first row is a header).
    public static func parseZips(_ csv: String) -> [String: LatLon] {
        var m: [String: LatLon] = [:]
        m.reserveCapacity(45_000)
        for line in csv.split(whereSeparator: \.isNewline).dropFirst() {
            let p = line.split(separator: ",", omittingEmptySubsequences: false)
            guard p.count >= 3, let lat = Double(p[1]), let lon = Double(p[2]) else { continue }
            m[String(p[0])] = LatLon(lat: lat, lon: lon)
        }
        return m
    }

    /// A valid US zip is exactly five digits. Returns the cleaned zip (ZIP+4 suffix dropped) or nil.
    public static func cleanZip(_ raw: String) -> String? {
        let z = raw.trimmingCharacters(in: .whitespaces).split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        return z.count == 5 && z.allSatisfy({ $0.isASCII && $0.isNumber }) ? z : nil
    }

    public static func distanceKm(_ a: LatLon, _ b: LatLon) -> Double {
        let r = 6371.0
        func rad(_ d: Double) -> Double { d * Double.pi / 180 }
        let dLat = rad(b.lat - a.lat), dLon = rad(b.lon - a.lon)
        let h = pow(sin(dLat / 2), 2) + cos(rad(a.lat)) * cos(rad(b.lat)) * pow(sin(dLon / 2), 2)
        return 2 * r * asin(min(1, sqrt(h)))
    }

    /// Markets ordered nearest first.
    public static func nearest(_ point: LatLon, _ markets: [Market], limit: Int = 5) -> [Market] {
        Array(markets.sorted { distanceKm(point, LatLon(lat: $0.lat, lon: $0.lon)) < distanceKm(point, LatLon(lat: $1.lat, lon: $1.lon)) }.prefix(limit))
    }

    public static func marketsForZip(_ zip: String, zips: [String: LatLon], markets: [Market], limit: Int = 5) -> [Market] {
        guard let z = cleanZip(zip), let p = zips[z] else { return [] }
        return nearest(p, markets, limit: limit)
    }

    /// The zip whose centroid is closest to a point (turns an approximate location into a zip the user confirms).
    public static func nearestZip(_ point: LatLon, zips: [String: LatLon]) -> String? {
        var best: (String, Double)?
        for (z, p) in zips {
            let d = distanceKm(point, p)
            if best == nil || d < best!.1 { best = (z, d) }
        }
        return best?.0
    }

    // The feed has a few misspelt market names; fold them onto the market list before matching.
    private static let aliases: [(String, String)] = [("kirksvill", "kirksville"), ("alburquerque", "albuquerque"),
                                                      ("forth worth", "fort worth"), ("fortworth", "fort worth")]

    private static func norm(_ s: String) -> String {
        var n = s.lowercased().trimmingCharacters(in: .whitespaces)
        while n.hasSuffix(".") || n.hasSuffix(" ") { n.removeLast() }
        for (from, to) in aliases where n.hasSuffix(from) { n = String(n.dropLast(from.count)) + to }
        return n
    }

    /// Which market a feed channel belongs to, from the market name at the end of its name
    /// ("CBS El Paso", "US - NBC News Dallas Fortworth"). Longest market name wins. nil = national / unknown.
    public static func marketOfChannel(_ channelName: String, markets: [Market]) -> Market? {
        let n = norm(channelName)
        var best: Market?
        for m in markets {
            let mn = m.name.lowercased()
            let hit: Bool
            if n == mn { hit = true }
            else if n.hasSuffix(mn) {
                let before = n[n.index(n.endIndex, offsetBy: -mn.count - 1)]
                hit = !before.isLetter
            } else { hit = false }
            if hit && (best == nil || m.name.count > best!.name.count) { best = m }
        }
        return best
    }

    /// Channels to keep for a market: those whose name ends with the market, plus channels that name no market at all
    /// (national digital networks that the local feed carries). Same rule as Android.
    public static func channelsFor(_ market: Market, channels: [Channel], markets: [Market]) -> [Channel] {
        channels.filter { c in
            guard let m = marketOfChannel(c.name, markets: markets) else { return true }
            return m.id == market.id
        }
    }

    public static func filterFor(_ market: Market, data: GuideData, markets: [Market]) -> GuideData {
        let ch = channelsFor(market, channels: data.channels, markets: markets)
        let ids = Set(ch.map(\.id))
        return GuideData(channels: ch, programs: data.programs.filter { ids.contains($0.channelId) })
    }
}

/// Streaming / TV sources offered in setup. Labels only: lineups differ per subscriber, so numbers stay editable.
public struct Provider: Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let note: String
}

public enum Providers {
    public static let all: [Provider] = [
        Provider(id: "antenna", label: "Antenna (over the air)", note: "Local channel numbers match your antenna."),
        Provider(id: "cable", label: "Cable or satellite", note: "Numbers come from the broadcast feed; edit them to match your box."),
        Provider(id: "youtubetv", label: "YouTube TV", note: "Local channels shown; edit numbers to match your lineup."),
        Provider(id: "hulu", label: "Hulu + Live TV", note: "Local channels shown; edit numbers to match your lineup."),
        Provider(id: "sling", label: "Sling TV", note: "Local channels vary by plan; edit numbers as needed."),
        Provider(id: "fubo", label: "Fubo", note: "Local channels shown; edit numbers to match your lineup."),
        Provider(id: "directv", label: "DirecTV Stream", note: "Local channels shown; edit numbers to match your lineup."),
        Provider(id: "philo", label: "Philo", note: "Philo carries few local channels; listings may include channels you can't watch."),
        Provider(id: "other", label: "Something else", note: "Listings are for your local market's broadcast channels."),
    ]
    public static func byId(_ id: String) -> Provider { all.first { $0.id == id } ?? all[all.count - 1] }
}
