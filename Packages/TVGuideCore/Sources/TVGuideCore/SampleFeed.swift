import Foundation

/// Clearly-labelled preview data. Used when the live feed is disabled (production builds without a recorded
/// EPGTalk approval) and for development. It is generated, not copied from any provider.
public enum SampleFeed {
    public static let channelNames: [(String, String)] = [
        ("2.1", "Sample CBS"), ("4.1", "Sample NBC"), ("5.1", "Sample FOX"), ("7.1", "Sample ABC"),
        ("11.1", "Sample CW"), ("13.1", "Sample PBS"), ("24.1", "Sample News Channel"),
    ]
    private static let titles = ["Morning Show", "Local News", "Game Time", "Cooking Together", "Evening News", "Mystery Hour",
                                 "Nature Walk", "Comedy Night", "Late Talk", "Movie of the Week", "Science Today", "Music Special"]
    private static let slots: [Int] = [60, 30, 90, 60, 30, 60, 120, 30]   // minutes

    public static func generate(now: Int64) -> GuideData {
        let hour: Int64 = 3_600_000
        let start = (now / hour) * hour - 3 * hour
        let end = start + 75 * hour
        var channels: [Channel] = []
        var programs: [Program] = []
        for (i, c) in channelNames.enumerated() {
            let id = "sample.\(i)"
            channels.append(Channel(id: id, name: c.1, feedNumber: c.0))
            var t = start
            var n = i
            while t < end {
                let len = Int64(slots[(n + i) % slots.count]) * 60_000
                let title = titles[(n * 3 + i) % titles.count]
                programs.append(Program(channelId: id, title: title,
                                        description: "Sample listing for preview only. This is not a real schedule.",
                                        startMillis: t, stopMillis: t + len))
                t += len; n += 1
            }
        }
        return GuideData(channels: channels, programs: programs)
    }
}
