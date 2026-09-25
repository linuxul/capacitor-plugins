import Foundation
import UIKit
import Capacitor

@objc(SplashScreenPlugin)
public class SplashScreenPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "SplashScreenPlugin"
    public let jsName = "SplashScreen"
    public let pluginMethods: [CAPPluginMethod] = [
        .promise("show", SplashScreenPlugin.show),
        .promise("hide", SplashScreenPlugin.hide)
    ]
    private var splashScreen: SplashScreen?

    override public func load() {
        if let view = bridge?.viewController?.view {
            splashScreen = SplashScreen(parentView: view, config: splashScreenConfig())
            splashScreen?.showOnLaunch()
        }
    }

    // show and hide stay synchronous: the bridge queue runs them in the order of the calls and the splash screen hands
    // the UIKit work to the main queue in that order, so a hide after a show wins. Async methods would not keep that
    // order.

    // Show the splash screen
    public func show(_ call: CAPPluginCall) throws {
        guard let splash = splashScreen else {
            throw CAPPluginError("Unable to show Splash Screen")
        }
        let settings = splashScreenSettings(from: call)
        splash.show(settings: settings,
                    completion: {
                        call.resolve()
                    })
    }

    // Hide the splash screen
    public func hide(_ call: CAPPluginCall) throws {
        guard let splash = splashScreen else {
            throw CAPPluginError("Unable to hide Splash Screen")
        }
        let settings = splashScreenSettings(from: call)
        splash.hide(settings: settings)
        call.resolve()
    }

    private func splashScreenSettings(from call: CAPPluginCall) -> SplashScreenSettings {
        var settings = SplashScreenSettings()

        if let showDuration = call.getInt("showDuration") {
            settings.showDuration = showDuration
        }
        if let fadeInDuration = call.getInt("fadeInDuration") {
            settings.fadeInDuration = fadeInDuration
        }
        if let fadeOutDuration = call.getInt("fadeOutDuration") {
            settings.fadeOutDuration = fadeOutDuration
        }
        if let autoHide = call.getBool("autoHide") {
            settings.autoHide = autoHide
        }
        return settings
    }

    private func splashScreenConfig() -> SplashScreenConfig {
        var config = SplashScreenConfig()

        if let backgroundColor = getConfig().getString("backgroundColor") {
            config.backgroundColor = UIColor.capacitor.color(fromHex: backgroundColor)
        }
        if let spinnerStyle = getConfig().getString("iosSpinnerStyle") {
            switch spinnerStyle.lowercased() {
            case "small":
                config.spinnerStyle = .medium
            default:
                config.spinnerStyle = .large
            }
        }
        if let spinnerColor = getConfig().getString("spinnerColor") {
            config.spinnerColor = UIColor.capacitor.color(fromHex: spinnerColor)
        }
        config.showSpinner = getConfig().getBoolean("showSpinner", config.showSpinner)

        config.launchShowDuration = getConfig().getInt("launchShowDuration", config.launchShowDuration)
        config.launchAutoHide = getConfig().getBoolean("launchAutoHide", config.launchAutoHide)
        return config
    }

}
