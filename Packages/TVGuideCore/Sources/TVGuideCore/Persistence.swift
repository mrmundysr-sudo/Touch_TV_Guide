import Foundation

/// Small atomic JSON file store (Application Support). Every file is independent, so a failure to read or write one
/// (for example the guide) never touches another (for example the user's customization).
public struct FileStore: Sendable {
    public let directory: URL
    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func url(_ name: String) -> URL { directory.appendingPathComponent(name) }

    public func read<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let d = try? Data(contentsOf: url(name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }

    public func write<T: Encodable>(_ value: T, _ name: String) throws {
        let d = try JSONEncoder().encode(value)
        try d.write(to: url(name), options: .atomic)
    }

    public func readData(_ name: String) -> Data? { try? Data(contentsOf: url(name)) }
    public func writeData(_ d: Data, _ name: String) throws { try d.write(to: url(name), options: .atomic) }
    public func exists(_ name: String) -> Bool { FileManager.default.fileExists(atPath: url(name).path) }
    public func remove(_ name: String) { try? FileManager.default.removeItem(at: url(name)) }
}
