import XCTest
@testable import VoxLib

final class VoxLibTests: XCTestCase {
    func testSpeechRecognizerInit() {
        let recognizer = SpeechRecognizer()
        XCTAssertNotNil(recognizer)
    }
}
