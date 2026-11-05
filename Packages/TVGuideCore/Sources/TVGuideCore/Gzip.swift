import Foundation
#if canImport(Compression)
import Compression
#endif

public enum GzipError: Error, LocalizedError {
    case notGzip, truncated, unsupported
    public var errorDescription: String? { "The guide file couldn't be unpacked." }
}

/// Minimal gzip reader: parses the RFC 1952 header and inflates the raw deflate payload with Apple's Compression framework.
public enum Gzip {
    public static func isGzip(_ d: Data) -> Bool { d.count > 2 && d[d.startIndex] == 0x1f && d[d.startIndex + 1] == 0x8b }

    /// Returns the data unchanged if it isn't gzip.
    public static func decompressIfNeeded(_ d: Data) throws -> Data { isGzip(d) ? try decompress(d) : d }

    public static func decompress(_ input: Data) throws -> Data {
        let d = [UInt8](input)
        guard d.count >= 18, d[0] == 0x1f, d[1] == 0x8b, d[2] == 8 else { throw GzipError.notGzip }
        let flags = d[3]
        var i = 10
        if flags & 0x04 != 0 {                       // FEXTRA
            guard i + 2 <= d.count else { throw GzipError.truncated }
            i += 2 + Int(d[i]) + (Int(d[i + 1]) << 8)
        }
        if flags & 0x08 != 0 { while i < d.count && d[i] != 0 { i += 1 }; i += 1 }   // FNAME
        if flags & 0x10 != 0 { while i < d.count && d[i] != 0 { i += 1 }; i += 1 }   // FCOMMENT
        if flags & 0x02 != 0 { i += 2 }                                               // FHCRC
        guard i < d.count - 8 else { throw GzipError.truncated }
        let payload = Data(d[i..<(d.count - 8)])
        #if canImport(Compression)
        do { return try (payload as NSData).decompressed(using: .zlib) as Data }
        catch { throw GzipError.truncated }
        #else
        throw GzipError.unsupported
        #endif
    }

    #if canImport(Compression)
    /// Used by tests and the sample feed to build gzip fixtures.
    public static func compress(_ input: Data) throws -> Data {
        let deflated = try (input as NSData).compressed(using: .zlib) as Data
        var out = Data([0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 0, 3])
        out.append(deflated)
        out.append(Data(repeating: 0, count: 8))      // CRC32 + ISIZE are not verified on read
        return out
    }
    #endif
}
