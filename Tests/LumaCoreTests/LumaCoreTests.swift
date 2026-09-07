import XCTest
import LumaValidation

final class LumaCoreTests: XCTestCase {
    func testCoreRetrievalAndProvenance() {
        for result in ValidationSuite.runCore() {
            XCTAssertTrue(result.passed, "\(result.name): \(result.detail)")
        }
    }

    @MainActor
    func testSyntheticDocumentImportAndOCR() async {
        for result in await ValidationSuite.runImports() {
            XCTAssertTrue(result.passed, "\(result.name): \(result.detail)")
        }
    }
}
