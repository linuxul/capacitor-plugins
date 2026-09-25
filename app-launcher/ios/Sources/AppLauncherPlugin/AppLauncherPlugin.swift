import Foundation
import UIKit
import Capacitor

@objc(AppLauncherPlugin)
public class AppLauncherPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "AppLauncherPlugin"
    public let jsName = "AppLauncher"
    public let pluginMethods: [CAPPluginMethod] = [
        .async("canOpenUrl", AppLauncherPlugin.canOpenUrl),
        .async("openUrl", AppLauncherPlugin.openUrl)
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

    /// UIApplication is UIKit: the method runs on the main actor, and returns `{ completed }` once the system has
    /// tried to open the URL.
    @MainActor
    func openUrl(_ call: CAPPluginCall) async throws -> JSObject {
        guard let urlString = call.getString("url") else {
            throw CAPPluginError("Must supply a URL")
        }

        guard let url = URL.init(string: urlString) else {
            throw CAPPluginError("Invalid URL")
        }

        let completed = await UIApplication.shared.open(url, options: [:])
        return [
            "completed": completed
        ]
    }
}
