import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public enum XmltvError: Error, Equatable, LocalizedError {
    case malformed
    case empty
    public var errorDescription: String? {
        switch self {
        case .malformed: return "The guide file couldn't be read."
        case .empty: return "That file doesn't look like a TV guide."
        }
    }
}

/// SAX-based XMLTV parser. Tolerant of bad programmes (skipped) but fails closed on a malformed or truncated
/// document so a half-downloaded file can never replace a good cache.
public enum XmltvParser {
    public static func parse(_ data: Data) throws -> GuideData {
        let handler = Handler()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false   // the feed declares <!DOCTYPE tv SYSTEM "xmltv.dtd">
        parser.delegate = handler
        guard parser.parse() else { throw XmltvError.malformed }
        let programs = handler.programs.sorted {
            $0.channelId != $1.channelId ? $0.channelId < $1.channelId : $0.startMillis < $1.startMillis
        }
        return GuideData(channels: handler.channelOrder.compactMap { handler.channels[$0] }, programs: programs)
    }

    private static func isNumber(_ s: String) -> Bool {
        guard !s.isEmpty else { return false }
        var dots = 0
        for (i, ch) in s.enumerated() {
            if ch == "." { dots += 1; if i == 0 || i == s.count - 1 || dots > 1 { return false } }
            else if !(ch.isASCII && ch.isNumber) { return false }
        }
        return true
    }

    private final class Handler: NSObject, XMLParserDelegate {
        var channels: [String: Channel] = [:]
        var channelOrder: [String] = []
        var programs: [Program] = []

        private var text = ""
        private var chId: String?
        private var names: [String] = []
        private var logo: String?
        private var pCh: String?
        private var pStart: Int64 = 0
        private var pStop: Int64 = 0
        private var title: String?
        private var desc: String?
        private var inChannel = false
        private var inProgramme = false

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            text = ""
            switch elementName {
            case "channel": inChannel = true; chId = attributeDict["id"]; names = []; logo = nil
            case "icon": if inChannel { logo = attributeDict["src"] }
            case "programme":
                inProgramme = true; pCh = attributeDict["channel"]; title = nil; desc = nil
                pStart = XmltvParser.parseTime(attributeDict["start"]); pStop = XmltvParser.parseTime(attributeDict["stop"])
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch elementName {
            case "display-name": if inChannel && !t.isEmpty { names.append(t) }
            case "lcn": if inChannel && !t.isEmpty { names.insert(t, at: 0) }
            case "channel":
                inChannel = false
                if let id = chId, !id.isEmpty {
                    let num = names.first { XmltvParser.isNumber($0) }
                    let name = names.first { !XmltvParser.isNumber($0) } ?? id
                    if channels[id] == nil { channelOrder.append(id) }
                    channels[id] = Channel(id: id, name: name, feedNumber: num, logoURL: logo)
                }
            case "title": if inProgramme && title == nil { title = t }
            case "desc": if inProgramme && desc == nil { desc = t.isEmpty ? nil : t }
            case "programme":
                inProgramme = false
                if let c = pCh, let ti = title, !ti.isEmpty, pStart > 0, pStop > pStart {
                    programs.append(Program(channelId: c, title: ti, description: desc, startMillis: pStart, stopMillis: pStop))
                }
            default: break
            }
        }
    }

    /// "20261105180000 +0000" or without offset (treated as UTC). Returns 0 if unparseable.
    public static func parseTime(_ s: String?) -> Int64 {
        guard let s = s?.trimmingCharacters(in: .whitespaces) else { return 0 }
        let u = Array(s.utf8)
        guard u.count >= 14 else { return 0 }
        func num(_ a: Int, _ n: Int) -> Int? {
            guard a + n <= u.count else { return nil }
            var v = 0
            for i in a..<(a + n) { let c = u[i]; guard c >= 48 && c <= 57 else { return nil }; v = v * 10 + Int(c - 48) }
            return v
        }
        guard let y = num(0, 4), let mo = num(4, 2), let d = num(6, 2), let h = num(8, 2), let mi = num(10, 2), let se = num(12, 2),
              (1...12).contains(mo), (1...31).contains(d), h < 24, mi < 60, se <= 60 else { return 0 }
        var offset = 0
        var i = 14
        while i < u.count && u[i] == 32 { i += 1 }
        if i < u.count {
            let sign: Int
            if u[i] == 43 { sign = 1 } else if u[i] == 45 { sign = -1 } else { return 0 }
            guard let oh = num(i + 1, 2), let om = num(i + 3, 2) else { return 0 }
            offset = sign * (oh * 3600 + om * 60)
        }
        let secs = daysFromCivil(y, mo, d) * 86_400 + h * 3600 + mi * 60 + se - offset
        return Int64(secs) * 1000
    }

    /// Days since 1970-01-01 (Howard Hinnant's algorithm).
    static func daysFromCivil(_ yIn: Int, _ m: Int, _ d: Int) -> Int {
        let y = m <= 2 ? yIn - 1 : yIn
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }
}
