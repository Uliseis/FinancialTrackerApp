import XCTest
@testable import CoreModel

final class CoreModelTests: XCTestCase {
    func testSchemaListsAllTypes() {
        XCTAssertEqual(CoreModelSchema.allTypes.count, 14)
    }
}
