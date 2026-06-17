import XCTest
@testable import CoreModel

final class CoreModelTests: XCTestCase {
    func testSchemaListsAllTypes() {
        // 14 synced @Model types + SyncRecordMeta (local-only sync bookkeeping).
        XCTAssertEqual(CoreModelSchema.allTypes.count, 15)
    }
}
