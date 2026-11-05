import Foundation

/// Pure guide rules shared by all UI. Mirrors docs/DATA_MODEL.md and the Android `GuideLogic`.
public enum GuideLogic {
    public static func effectiveNumber(_ c: Channel, _ cu: Customization) -> String {
        cu.numbers[c.id] ?? c.feedNumber ?? unknownNumber
    }

    private static func sortKey(_ n: String) -> Double { Double(n) ?? Double.greatestFiniteMagnitude }

    /// Numeric order; "?" (and anything non-numeric) always last, ties broken by name.
    public static func sortedByNumber(_ channels: [Channel], _ cu: Customization) -> [Channel] {
        channels.sorted { a, b in
            let ka = sortKey(effectiveNumber(a, cu)), kb = sortKey(effectiveNumber(b, cu))
            if ka != kb { return ka < kb }
            return a.name.lowercased() < b.name.lowercased()
        }
    }

    /// The order shown in the guide: the user's custom order first (if any), the rest by number.
    public static func sorted(_ channels: [Channel], _ cu: Customization) -> [Channel] {
        let byNumber = sortedByNumber(channels, cu)
        if cu.customOrder.isEmpty { return byNumber }
        var index: [String: Int] = [:]
        for (i, id) in cu.customOrder.enumerated() where index[id] == nil { index[id] = i }
        let ordered = byNumber.filter { index[$0.id] != nil }.sorted { index[$0.id]! < index[$1.id]! }
        return ordered + byNumber.filter { index[$0.id] == nil }
    }

    /// Store the order the user dragged the list into.
    public static func setOrder(_ cu: Customization, ids: [String]) -> Customization {
        var seen = Set<String>()
        var n = cu; n.customOrder = ids.filter { seen.insert($0).inserted }; return n
    }

    /// Assign [number] to a channel. If another channel already shows that number it becomes "?".
    /// Passing "?" simply unassigns. Returns a new Customization.
    public static func assignNumber(_ channels: [Channel], _ cu: Customization, channelId: String, number: String) -> Customization {
        let n = number.trimmingCharacters(in: .whitespaces)
        var map = cu.numbers
        if n != unknownNumber {
            for c in channels where c.id != channelId && effectiveNumber(c, cu) == n { map[c.id] = unknownNumber }
        }
        map[channelId] = n
        var out = cu; out.numbers = map; return out
    }

    /// Numbers shown by more than one channel (excluding "?"). Key = number. Some collisions are legitimate in the
    /// feed (for example two stations that both carry 11.1), so the UI flags them instead of hiding them.
    public static func duplicateNumbers(_ channels: [Channel], _ cu: Customization) -> [String: [Channel]] {
        var groups: [String: [Channel]] = [:]
        for c in channels {
            let n = effectiveNumber(c, cu)
            if n != unknownNumber { groups[n, default: []].append(c) }
        }
        return groups.filter { $0.value.count > 1 }
    }

    public static func category(_ c: Channel, _ cu: Customization) -> String? { cu.categories[c.id] ?? c.feedCategory }

    /// User assignment overrides feed tag; unassigned channels are excluded from category filters.
    public static func byCategory(_ channels: [Channel], _ cu: Customization, category cat: String) -> [Channel] {
        sorted(channels.filter { category($0, cu)?.lowercased() == cat.lowercased() }, cu)
    }

    public static func favorites(_ channels: [Channel], _ cu: Customization) -> [Channel] {
        sorted(channels.filter { cu.favoriteChannels.contains($0.id) }, cu)
    }

    public static func toggleFavoriteChannel(_ cu: Customization, _ id: String) -> Customization {
        var out = cu
        if out.favoriteChannels.contains(id) { out.favoriteChannels.remove(id) } else { out.favoriteChannels.insert(id) }
        return out
    }

    public static func toggleFavoriteProgram(_ cu: Customization, _ p: Program) -> Customization {
        var out = cu
        if out.favoritePrograms.contains(p.key) { out.favoritePrograms.remove(p.key) } else { out.favoritePrograms.insert(p.key) }
        return out
    }

    /// Programs overlapping [from, to) for one channel; an empty result means show "No listings".
    public static func window(_ programs: [Program], channelId: String, from: Int64, to: Int64) -> [Program] {
        programs.filter { $0.channelId == channelId && $0.stopMillis > from && $0.startMillis < to }
            .sorted { $0.startMillis < $1.startMillis }
    }

    /// Last data time: the right-hand navigation limit.
    public static func dataEnd(_ programs: [Program]) -> Int64 { programs.map(\.stopMillis).max() ?? 0 }

    /// Search channels (name or number) and programs (title/description), ordered by channel number.
    public static func search(_ data: GuideData, _ cu: Customization, query: String) -> (channels: [Channel], programs: [Program]) {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return ([], []) }
        let ordered = sorted(data.channels, cu)
        var order: [String: Int] = [:]
        for (i, c) in ordered.enumerated() where order[c.id] == nil { order[c.id] = i }
        let ch = ordered.filter { $0.name.lowercased().contains(q) || effectiveNumber($0, cu) == q }
        let pr = data.programs.filter { $0.title.lowercased().contains(q) || ($0.description?.lowercased().contains(q) ?? false) }
            .sorted { a, b in
                let oa = order[a.channelId] ?? Int.max, ob = order[b.channelId] ?? Int.max
                return oa != ob ? oa < ob : a.startMillis < b.startMillis
            }
        return (ch, pr)
    }

    /// Reset: clear custom numbers, categories and order (favorites kept). Restores the lineup defaults.
    public static func resetCustomization(_ cu: Customization) -> Customization {
        var out = cu; out.numbers = [:]; out.categories = [:]; out.customOrder = []; return out
    }
}
