import Foundation
import UIKit
import Capacitor

@objc(AppPlugin)
public class AppPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "AppPlugin"
    public let jsName = "App"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "exitApp", returnType: .promise),
        CAPPluginMethod(name: "getInfo", returnType: .promise),
        CAPPluginMethod(name: "getAppLanguage", returnType: .promise),
        CAPPluginMethod(name: "getLaunchUrl", returnType: .promise),
        CAPPluginMethod(name: "getState", returnType: .promise),
        CAPPluginMethod(name: "minimizeApp", returnType: .promise),
        CAPPluginMethod(name: "toggleBackButtonHandler", returnType: .promise)
    ]
    private var observers: [NSObjectProtocol] = []

    override public func load() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(self.handleUrlOpened(notification:)), name: Notification.Name.capacitorOpenURL, object: nil)
        center.addObserver(self,
                           selector: #selector(self.handleUniversalLink(notification:)),
                           name: Notification.Name.capacitorOpenUniversalLink,
                           object: nil)
        observe(UIApplication.didBecomeActiveNotification) { plugin in
            plugin.notifyListeners("appStateChange", data: [
                "isActive": true
            ])
        }
        observe(UIApplication.willResignActiveNotification) { plugin in
            plugin.notifyListeners("appStateChange", data: [
                "isActive": false
            ])
        }
        observe(UIApplication.didEnterBackgroundNotification) { plugin in
            plugin.notifyListeners("pause", data: nil)
        }
        observe(UIApplication.willEnterForegroundNotification) { plugin in
            plugin.notifyListeners("resume", data: nil)
        }
    }

    /// Runs `handler` on the main queue for every `name` notification while the plugin is alive.
    private func observe(_ name: Notification.Name, _ handler: @escaping (AppPlugin) -> Void) {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: OperationQueue.main) { [weak self] (_) in
            guard let self else {
                return
            }
            handler(self)
        })
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    @objc func handleUrlOpened(notification: NSNotification) {
        guard let object = notification.object as? [String: Any?] else {
            return
        }

        notifyListeners("appUrlOpen", data: makeUrlOpenObject(object), retainUntilConsumed: true)
    }

    @objc func handleUniversalLink(notification: NSNotification) {
        guard let object = notification.object as? [String: Any?] else {
            return
        }

        notifyListeners("appUrlOpen", data: makeUrlOpenObject(object), retainUntilConsumed: true)
    }

    func makeUrlOpenObject(_ object: [String: Any?]) -> JSObject {
        guard let url = object["url"] as? NSURL else {
            return [:]
        }

        let options = object["options"] as? [String: Any?] ?? [:]
        return [
            "url": url.absoluteString ?? "",
            "iosSourceApplication": options[UIApplication.OpenURLOptionsKey.sourceApplication.rawValue] as? String ?? "",
            "iosOpenInPlace": options[UIApplication.OpenURLOptionsKey.openInPlace.rawValue] as? String ?? ""
        ]
    }

    @objc func exitApp(_ call: CAPPluginCall) {
        call.unimplemented()
    }

    @objc func getInfo(_ call: CAPPluginCall) {
        if let info = Bundle.main.infoDictionary {
            call.resolve([
                "name": info["CFBundleDisplayName"] as? String ?? "",
                "id": info["CFBundleIdentifier"] as? String ?? "",
                "build": info["CFBundleVersion"] as? String ?? "",
                "version": info["CFBundleShortVersionString"] as? String ?? ""
            ])
        } else {
            call.reject("Unable to get App Info")
        }

    }

    @objc func getLaunchUrl(_ call: CAPPluginCall) {
        // Settle once: with a launch URL the call used to resolve with it and then resolve again without data.
        if let result = AppPlugin.launchUrlResult(ApplicationDelegateProxy.shared.lastURL) {
            call.resolve(result)
        } else {
            call.resolve()
        }
    }

    /// The result of `getLaunchUrl`: `{ url }` when the app was opened with a URL, nil (resolve with no data) otherwise.
    static func launchUrlResult(_ url: URL?) -> JSObject? {
        guard let url else {
            return nil
        }
        return ["url": url.absoluteString]
    }

    @objc func getState(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            call.resolve([
                "isActive": UIApplication.shared.applicationState == UIApplication.State.active
            ])
        }
    }

    @objc func minimizeApp(_ call: CAPPluginCall) {
        call.unimplemented()
    }

    @objc func getAppLanguage(_ call: CAPPluginCall) {
        call.resolve([
            "value": Bundle.main.preferredLocalizations.first ?? ""
        ])
    }

    @objc func toggleBackButtonHandler(_ call: CAPPluginCall) {
        call.unimplemented()
    }
}
