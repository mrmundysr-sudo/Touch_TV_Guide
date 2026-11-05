import Foundation

/// Feed data. Never modified by user customization.
public struct Channel: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public var feedNumber: String?
    public var logoURL: String?
    public var feedCategory: String?
    public init(id: String, name: String, feedNumber: String? = nil, logoURL: String? = nil, feedCategory: String? = nil) {
        self.id = id; self.name = name; self.feedNumber = feedNumber; self.logoURL = logoURL; self.feedCategory = feedCategory
    }
}

public struct Program: Codable, Hashable, Identifiable, Sendable {
    public let channelId: String
    public let title: String
    public let description: String?
    public let startMillis: Int64
    public let stopMillis: Int64
    public init(channelId: String, title: String, description: String?, startMillis: Int64, stopMillis: Int64) {
        self.channelId = channelId; self.title = title; self.description = description
        self.startMillis = startMillis; self.stopMillis = stopMillis
    }
    /// `channelId|startMillis`, identical to the Android contract.
    public var key: String { "\(channelId)|\(startMillis)" }
    public var id: String { key }
    public var start: Date { Date(timeIntervalSince1970: TimeInterval(startMillis) / 1000) }
    public var stop: Date { Date(timeIntervalSince1970: TimeInterval(stopMillis) / 1000) }
    public var durationMinutes: Int { Int((stopMillis - startMillis) / 60_000) }
}

public struct GuideData: Codable, Equatable, Sendable {
    public var channels: [Channel]
    public var programs: [Program]
    public init(channels: [Channel] = [], programs: [Program] = []) { self.channels = channels; self.programs = programs }
    public static let empty = GuideData()
}

/// User data, stored separately from feed data so a refresh never overwrites it.
public struct Customization: Codable, Equatable, Sendable {
    public var numbers: [String: String]          // channelId -> user number ("?" allowed)
    public var categories: [String: String]       // channelId -> user category
    public var favoriteChannels: Set<String>
    public var favoritePrograms: Set<String>      // Program.key
    /// iOS addition: a user-defined channel order. Empty = sort by channel number.
    public var customOrder: [String]

    public init(numbers: [String: String] = [:], categories: [String: String] = [:], favoriteChannels: Set<String> = [],
                favoritePrograms: Set<String> = [], customOrder: [String] = []) {
        self.numbers = numbers; self.categories = categories; self.favoriteChannels = favoriteChannels
        self.favoritePrograms = favoritePrograms; self.customOrder = customOrder
    }

    enum CodingKeys: String, CodingKey { case numbers, categories, favoriteChannels, favoritePrograms, customOrder }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        numbers = try c.decodeIfPresent([String: String].self, forKey: .numbers) ?? [:]
        categories = try c.decodeIfPresent([String: String].self, forKey: .categories) ?? [:]
        favoriteChannels = try c.decodeIfPresent(Set<String>.self, forKey: .favoriteChannels) ?? []
        favoritePrograms = try c.decodeIfPresent(Set<String>.self, forKey: .favoritePrograms) ?? []
        customOrder = try c.decodeIfPresent([String].self, forKey: .customOrder) ?? []
    }
}

/// Home profile: exactly one is kept. Customization lives beside it.
public struct HomeProfile: Codable, Equatable, Sendable {
    public var zip: String
    public var providerId: String
    public var marketId: String
    public init(zip: String, providerId: String, marketId: String) { self.zip = zip; self.providerId = providerId; self.marketId = marketId }
}

public let unknownNumber = "?"
