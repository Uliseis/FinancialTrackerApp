import XCTest
import Foundation
@testable import CoreSync

final class SyncStateStoreTests: XCTestCase {

    private func makeStore() -> (SyncStateStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("coresync-test-\(UUID().uuidString).data")
        return (SyncStateStore(fileURL: url), url)
    }

    func test_loadMissingFile_returnsNil() throws {
        let (store, _) = makeStore()
        XCTAssertNil(try store.load())
    }

    func test_clear_isIdempotentOnMissingFile() throws {
        let (store, _) = makeStore()
        XCTAssertNoThrow(try store.clear())
    }

    func test_clear_removesExistingFile() throws {
        let (store, url) = makeStore()
        try Data([0x00]).write(to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        try store.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func test_load_emptyFile_returnsNil() throws {
        let (store, url) = makeStore()
        try Data().write(to: url)
        XCTAssertNil(try store.load())
    }

    func test_defaultLocation_resolvesUnderApplicationSupport() throws {
        let url = try SyncStateStore.defaultLocation()
        XCTAssertTrue(url.path.contains("CoreSync"))
        XCTAssertTrue(url.lastPathComponent == "engineState.data")
    }
}
