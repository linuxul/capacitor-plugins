import Foundation
import Capacitor
import UIKit

@objc(ToastPlugin)
public class ToastPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "ToastPlugin"
    public let jsName = "Toast"
    public let pluginMethods: [CAPPluginMethod] = [
        .async("show", ToastPlugin.show)
    ]

    /// The toast is a view added to the bridge view controller's view, which is read on the main actor. The call
    /// resolves once the toast has faded out, as it did when the method finished in the animation's completion handler.
    @MainActor
    func show(_ call: CAPPluginCall) async throws {
        guard let text = call.getString("text") else {
            throw CAPPluginError("text must be provided and must be a string.")
        }
        let durationType = call.getString("duration", "short")
        let duration = durationType == "long" ? 3500 : 2000
        let position = call.getString("position", "bottom")

        guard let viewController = bridge?.viewController else {
            throw CAPPluginError("Unable to display toast!")
        }
        // UIKit calls the completion of an animation exactly once, also when the animation is interrupted.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Toast.showToast(in: viewController, text: text, duration: duration, position: position) { _ in
                continuation.resume()
            }
        }
    }
}
