import Foundation
import Capacitor
import UIKit

/**
 * StatusBar plugin. Requires "View controller-based status bar appearance" to
 * be "YES" in Info.plist
 */
@objc(StatusBarPlugin)
public class StatusBarPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "StatusBarPlugin"
    public let jsName = "StatusBar"
    public let pluginMethods: [CAPPluginMethod] = [
        .promise("setStyle", StatusBarPlugin.setStyle),
        .promise("setBackgroundColor", StatusBarPlugin.setBackgroundColor),
        .promise("show", StatusBarPlugin.show),
        .promise("hide", StatusBarPlugin.hide),
        .async("getInfo", StatusBarPlugin.getInfo),
        .promise("setOverlaysWebView", StatusBarPlugin.setOverlaysWebView)
    ]
    private var statusBar: StatusBar?
    private let statusBarVisibilityChanged = "statusBarVisibilityChanged"
    private let statusBarOverlayChanged = "statusBarOverlayChanged"

    override public func load() {
        guard let bridge = bridge else { return }
        statusBar = StatusBar(bridge: bridge, config: statusBarConfig())
    }

    private func statusBarConfig() -> StatusBarConfig {
        var config = StatusBarConfig()
        config.overlaysWebView = getConfig().getBoolean("overlaysWebView", config.overlaysWebView)
        if let colorConfig = getConfig().getString("backgroundColor"), let color = UIColor.capacitor.color(fromHex: colorConfig) {
            config.backgroundColor = color
        }
        if let configStyle = getConfig().getString("style") {
            config.style = style(fromString: configStyle)
        }
        return config
    }

    private func style(fromString: String) -> UIStatusBarStyle {
        switch fromString.lowercased() {
        case "dark", "lightcontent":
            return .lightContent
        case "light", "darkcontent":
            return .darkContent
        case "default":
            return .default
        default:
            return .default
        }
    }

    // The setters stay synchronous: the bridge queue runs them in the order of the calls and each hands its UIKit work
    // to the main queue in that order, so the last call wins. Async methods would not keep that order.

    func setStyle(_ call: CAPPluginCall) {
        let options = call.options
        if let styleString = options["style"] as? String {
            let barStyle = style(fromString: styleString)
            DispatchQueue.main.async { [weak self] in
                self?.statusBar?.setStyle(barStyle)
            }
        }
        call.resolve([:])
    }

    func setBackgroundColor(_ call: CAPPluginCall) throws {
        guard let hexString = call.options["color"] as? String else {
            throw CAPPluginError("Color must be provided")
        }
        guard let color = UIColor.capacitor.color(fromHex: hexString) else {
            throw CAPPluginError("Invalid color provided. Must be a hex string (ex: #ff0000)")
        }
        DispatchQueue.main.async { [weak self] in
            self?.statusBar?.setBackgroundColor(color)
        }
        call.resolve()
    }

    func hide(_ call: CAPPluginCall) {
        let animation = call.getString("animation", "FADE")
        DispatchQueue.main.async { [weak self] in
            self?.statusBar?.hide(animation: animation)
            guard let self, let info = self.statusBar?.getInfo() else {
                return
            }
            self.notifyListeners(self.statusBarVisibilityChanged, data: StatusBarPlugin.toDict(info))
        }
        call.resolve()
    }

    func show(_ call: CAPPluginCall) {
        let animation = call.getString("animation", "FADE")
        DispatchQueue.main.async { [weak self] in
            self?.statusBar?.show(animation: animation)
            guard let self, let info = self.statusBar?.getInfo() else {
                return
            }
            self.notifyListeners(self.statusBarVisibilityChanged, data: StatusBarPlugin.toDict(info))
        }
        call.resolve()
    }

    /// The status bar is UIKit state: the method runs on the main actor, not the bridge queue. Async methods do not
    /// keep the order of the calls, which is fine for a read; the setters stay synchronous so that they do.
    @MainActor
    func getInfo(_ call: CAPPluginCall) async throws -> JSObject {
        guard let info = statusBar?.getInfo() else {
            throw CAPPluginError("Unable to get the status bar info: the status bar is not available")
        }
        return StatusBarPlugin.toJSObject(info)
    }

    func setOverlaysWebView(_ call: CAPPluginCall) {
        // Like Android, a missing `overlay` means true.
        let overlay = call.getBool("overlay") ?? true
        DispatchQueue.main.async { [weak self] in
            self?.statusBar?.setOverlaysWebView(overlay)
            guard let self, let info = self.statusBar?.getInfo() else {
                return
            }
            self.notifyListeners(self.statusBarOverlayChanged, data: StatusBarPlugin.toDict(info))
        }
        call.resolve()
    }

    /// `toDict(info)` as a JSObject, the result of `getInfo`. The bridge sends it as the same JSON as the events.
    static func toJSObject(_ info: StatusBarInfo) -> JSObject {
        return JSTypes.coerceDictionaryToJSObject(toDict(info)) ?? [:]
    }

    /// The JavaScript form of `info`. Every field of `StatusBarInfo` is optional, so a missing one falls back to the
    /// value the plugin starts with instead of crashing.
    static func toDict(_ info: StatusBarInfo) -> [String: Any] {
        return [
            "visible": info.visible ?? true,
            "style": info.style ?? "DEFAULT",
            "color": info.color ?? "",
            "overlays": info.overlays ?? true,
            "height": info.height ?? 0
        ]
    }
}
