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
        CAPPluginMethod(name: "setStyle", returnType: .promise),
        CAPPluginMethod(name: "setBackgroundColor", returnType: .promise),
        CAPPluginMethod(name: "show", returnType: .promise),
        CAPPluginMethod(name: "hide", returnType: .promise),
        CAPPluginMethod(name: "getInfo", returnType: .promise),
        CAPPluginMethod(name: "setOverlaysWebView", returnType: .promise)
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

    @objc func setStyle(_ call: CAPPluginCall) {
        let options = call.options
        if let styleString = options["style"] as? String {
            let barStyle = style(fromString: styleString)
            DispatchQueue.main.async { [weak self] in
                self?.statusBar?.setStyle(barStyle)
            }
        }
        call.resolve([:])
    }

    @objc func setBackgroundColor(_ call: CAPPluginCall) {
        guard let hexString = call.options["color"] as? String else {
            call.reject("Color must be provided")
            return
        }
        guard let color = UIColor.capacitor.color(fromHex: hexString) else {
            call.reject("Invalid color provided. Must be a hex string (ex: #ff0000)")
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.statusBar?.setBackgroundColor(color)
        }
        call.resolve()
    }

    @objc func hide(_ call: CAPPluginCall) {
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

    @objc func show(_ call: CAPPluginCall) {
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

    @objc func getInfo(_ call: CAPPluginCall) {
        DispatchQueue.main.async { [weak self] in
            guard let info = self?.statusBar?.getInfo() else {
                call.reject("Unable to get the status bar info: the status bar is not available")
                return
            }
            call.resolve(StatusBarPlugin.toDict(info))
        }
    }

    @objc func setOverlaysWebView(_ call: CAPPluginCall) {
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
