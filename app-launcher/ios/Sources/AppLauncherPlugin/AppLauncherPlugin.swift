import Foundation
import UIKit
import Capacitor

@objc(AppLauncherPlugin)
public class AppLauncherPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "AppLauncherPlugin"
    public let jsName = "AppLauncher"
    public let pluginMethods: [CAPPluginMethod] = [
        .async("canOpenUrl", AppLauncherPlugin.canOpenUrl),
        .promise("openUrl", AppLauncherPlugin.openUrl)
    ]

    /// UIApplication is UIKit: the method runs on the main actor, not the bridge queue.
    @MainActor
    func canOpenUrl(_ call: CAPPluginCall) async throws -> JSObject {
        guard let urlString = call.getString("url") else {
            throw CAPPluginError("Must supply a URL")
        }

        guard let url = URL.init(string: urlString) else {
            throw CAPPluginError("Invalid URL")
        }

        return [
            "value": UIApplication.shared.canOpenURL(url)
        ]
    }

    func openUrl(_ call: CAPPluginCall) {
        guard let urlString = call.getString("url") else {
            call.reject("Must supply a URL")
            return
        }

        guard let url = URL.init(string: urlString) else {
            call.reject("Invalid URL")
            return
        }

        DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:]) { (completed) in
                call.resolve([
                    "completed": completed
                ])
            }
        }
    }
}
