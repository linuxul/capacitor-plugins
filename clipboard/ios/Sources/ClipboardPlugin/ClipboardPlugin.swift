import Foundation
import Capacitor

@objc(ClipboardPlugin)
public class ClipboardPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "ClipboardPlugin"
    public let jsName = "Clipboard"
    public let pluginMethods: [CAPPluginMethod] = [
        .promise("read", ClipboardPlugin.read),
        .promise("write", ClipboardPlugin.write)
    ]
    private let implementation = Clipboard()

    // UIPasteboard is thread-safe (Sendable, not main-actor), so read and write stay synchronous on the bridge queue
    // and keep the order of the calls: a read after a write sees what was written.

    func read(_ call: CAPPluginCall) throws {
        let result = implementation.read()

        guard !result.isEmpty else {
            throw CAPPluginError("There is no data on the clipboard")
        }
        call.resolve(result)
    }

    func write(_ call: CAPPluginCall) throws {
        var result: Result<Void, Error>

        if let string = call.options["string"] as? String {
            result = implementation.write(content: string, ofType: Clipboard.ContentType.string)
        } else if let urlString = call.options["url"] as? String {
            result = implementation.write(content: urlString, ofType: Clipboard.ContentType.url)
        } else if let imageBase64 = call.options["image"] as? String {
            result = implementation.write(content: imageBase64, ofType: Clipboard.ContentType.image)
        } else {
            throw CAPPluginError("No content provided")
        }

        switch result {
        case .success:
            call.resolve()
        case .failure(let err):
            CAPLog.print(err.localizedDescription)
            throw CAPPluginError(err.localizedDescription, underlyingError: err)
        }
    }
}
