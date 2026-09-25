import Foundation
import UIKit
import Capacitor

@objc(ScreenReaderPlugin)
public class ScreenReaderPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "ScreenReaderPlugin"
    public let jsName = "ScreenReader"
    public let pluginMethods: [CAPPluginMethod] = [
        .promise("speak", ScreenReaderPlugin.speak),
        .async("isEnabled", ScreenReaderPlugin.isEnabled)
    ]
    static let stateChangeEvent = "stateChange"

    override public func load() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.onVoiceOverStateChanged(notification:)),
                                               name: UIAccessibility.voiceOverStatusDidChangeNotification,
                                               object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// UIAccessibility is UIKit state: the method runs on the main actor, not the bridge queue.
    @MainActor
    func isEnabled(_ call: CAPPluginCall) async -> JSObject {
        return [
            "value": UIAccessibility.isVoiceOverRunning
        ]
    }

    /// Stays synchronous so that announcements keep the order of the calls, which async methods do not. The
    /// announcement is made on the main queue a moment later, as before, and VoiceOver is checked there: it used to be
    /// read on the bridge queue.
    func speak(_ call: CAPPluginCall) throws {
        guard let value = call.getString("value") else {
            throw CAPPluginError("No value provided")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if UIAccessibility.isVoiceOverRunning {
                UIAccessibility.post(notification: .announcement, argument: value)
            }
        }

        call.resolve()
    }

    @objc private func onVoiceOverStateChanged(notification: NSNotification) {
        notifyListeners(ScreenReaderPlugin.stateChangeEvent, data: [
            "value": UIAccessibility.isVoiceOverRunning
        ])
    }
}
