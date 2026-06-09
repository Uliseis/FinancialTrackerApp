import Foundation
import CloudKit

public struct SyncStateStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func defaultLocation() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent("CoreSync", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("engineState.data", isDirectory: false)
    }

    public func load() throws -> CKSyncEngine.State.Serialization? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        if data.isEmpty { return nil }
        return try JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    public func save(_ state: CKSyncEngine.State.Serialization) throws {
        let data = try JSONEncoder().encode(state)
        try data.write(to: fileURL, options: [.atomic])
    }

    public func clear() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }
}
