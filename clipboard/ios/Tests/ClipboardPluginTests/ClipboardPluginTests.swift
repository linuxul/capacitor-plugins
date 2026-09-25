import XCTest
import Capacitor
@testable import ClipboardPlugin

// These tests only take paths that fail before writing: the simulator's pasteboard can be shared with the Mac's.
final class ClipboardTests: XCTestCase {
    func testWriteWithoutContentIsRejected() {
        XCTAssertEqual(writeError(["unrelated": "value"])?.message, "No content provided")
    }

    func testWriteOfAnUnreadableImageIsRejected() {
        let error = writeError(["image": "data:image/png;base64,bm90IGFuIGltYWdl"])
        XCTAssertEqual(error?.message, "Unable to encode image")
        XCTAssertNil(error?.code)
    }

    func testWriteOfAnInvalidUrlIsRejected() {
        XCTAssertEqual(writeError(["url": ""])?.message, "Unable to form URL")
    }

    /// The error write throws, which the bridge rejects the call with; nil when it returns.
    private func writeError(_ options: JSObject) -> CAPPluginError? {
        let call = CAPPluginCall(callbackId: "test", methodName: "write", options: options, success: { _, _ in
            XCTFail("write must not resolve")
        }, error: { _ in
            XCTFail("write answers by throwing")
        })
        do {
            try ClipboardPlugin().write(call)
            XCTFail("write must throw")
            return nil
        } catch let error as CAPPluginError {
            return error
        } catch {
            XCTFail("unexpected error \(error)")
            return nil
        }
    }
}
