import Foundation
import Security

/// Local settings and secrets. Lives outside the repo, in Application Support,
/// so nothing secret can be committed. `config.example.json` in the repo shows the shape.
public struct Config: Codable, Sendable {
    public var port: Int
    /// Every call to the local server must carry this. Generated on first run.
    public var token: String
    /// Notion internal integration token, for the Ready to delegate list. Set with `cr set-notion-token`.
    public var notionToken: String?
    /// Which Notion data source to read. Defaults to Task Tracker.
    public var notionDataSource: String?

    /// Saves changes, keeping the file private to Nina's account.
    public func save() throws {
        let data = try JSONEncoder.controlRoom.encode(self)
        try data.write(to: Config.fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Config.fileURL.path)
    }

    /// ~/Library/Application Support/Control Room, or CONTROL_ROOM_HOME if set (used by tests).
    public static var directory: URL {
        if let override = ProcessInfo.processInfo.environment["CONTROL_ROOM_HOME"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Control Room", isDirectory: true)
    }

    public static var fileURL: URL { directory.appendingPathComponent("config.local.json") }

    /// Reads the config, creating it with a fresh token the first time.
    public static func loadOrCreate() throws -> Config {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: fileURL) {
            return try JSONDecoder.controlRoom.decode(Config.self, from: data)
        }
        let config = Config(port: 47821, token: makeToken())
        let data = try JSONEncoder.controlRoom.encode(config)
        try data.write(to: fileURL, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        return config
    }

    private static func makeToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

extension JSONEncoder {
    public static var controlRoom: JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}

extension JSONDecoder {
    public static var controlRoom: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
