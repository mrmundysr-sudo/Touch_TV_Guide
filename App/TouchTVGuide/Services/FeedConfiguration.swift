import Foundation
import TVGuideCore

/// The single boundary between the app and the listings provider. Everything that must change when the approved
/// feed, its terms, or its attribution change lives here (see docs/FEED_CONFIGURATION.md).
enum FeedConfiguration {
    /// EPGTalk "US Local" guide: ~140 local markets, ~72 hours of listings, one XMLTV file.
    static let defaultURL = URL(string: "https://raw.githubusercontent.com/acidjesuz/EPGTalk/master/US_local_guide.xml.gz")!
    /// Alternative documented by EPGTalk.
    static let alternateURL = URL(string: "https://epgtalk.com/US_local_guide.xml.gz")!

    static let attributionName = "EPGTalk"
    static let attributionURL = URL(string: "https://epgtalk.com")!
    static let attributionLine = "Listings from EPGTalk (epgtalk.com)."
    static let zipDataAttribution = "Zip positions derive from US Census Bureau data via the MIT-licensed US-Zip-Codes-JSON list."

    static let userAgent = "TouchTVGuide-iOS/1.0 (personal TV listings app; fetches once a day)"
    static let maxDownloadBytes = 80 * 1024 * 1024

    /// Build-time gate (Info.plist `TVGLiveFeedEnabled`, from the `TVG_LIVE_FEED_ENABLED` build setting).
    /// NO means the app only offers the clearly-labelled sample preview data.
    static var liveFeedEnabledInBuild: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "TVGLiveFeedEnabled") as? String)?.uppercased() == "YES"
    }

    /// Whether the EPGTalk terms have been recorded in docs/EPGTALK_PERMISSION.md and flagged in Info.plist.
    static var termsRecorded: Bool { (Bundle.main.object(forInfoDictionaryKey: "TVGEPGTalkTermsRecorded") as? Bool) ?? false }

    static func isAcceptable(_ s: String) -> Bool {
        guard let u = URL(string: s.trimmingCharacters(in: .whitespaces)), u.scheme == "https", u.host != nil else { return false }
        return true
    }
}

/// URLSession-based downloader. Streams to memory with a hard size cap.
struct URLSessionDownloader: FeedDownloading {
    func download(_ url: URL) async throws -> Data {
        guard url.scheme == "https" else { throw URLError(.appTransportSecurityRequiresSecureConnection) }
        var req = URLRequest(url: url, timeoutInterval: 60)
        req.setValue(FeedConfiguration.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw DownloadError.status((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        if data.count > FeedConfiguration.maxDownloadBytes { throw DownloadError.tooLarge }
        return data
    }

    enum DownloadError: LocalizedError {
        case status(Int), tooLarge
        var errorDescription: String? {
            switch self {
            case .status(let c): return "The guide server answered \(c)."
            case .tooLarge: return "The guide file is unexpectedly large."
            }
        }
    }
}
