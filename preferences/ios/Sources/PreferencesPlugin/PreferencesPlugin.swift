import Foundation
import Capacitor

@objc(PreferencesPlugin)
public class PreferencesPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "PreferencesPlugin"
    public let jsName = "Preferences"
    public let pluginMethods: [CAPPluginMethod] = [
        .promise("configure", PreferencesPlugin.configure),
        .promise("get", PreferencesPlugin.get),
        .promise("set", PreferencesPlugin.set),
        .promise("remove", PreferencesPlugin.remove),
        .promise("keys", PreferencesPlugin.keys),
        .promise("clear", PreferencesPlugin.clear),
        .promise("migrate", PreferencesPlugin.migrate),
        .promise("removeOld", PreferencesPlugin.removeOld)
    ]
    private var preferences = Preferences(with: PreferencesConfiguration())

    // Every method is synchronous: the bridge calls them one after the other on its queue, so a get sees the set and
    // remove calls made before it. Async methods would not keep that order.

    func configure(_ call: CAPPluginCall) {
        let group = call.getString("group")
        let configuration: PreferencesConfiguration

        if let group = group {
            if group == "NativeStorage" {
                configuration = PreferencesConfiguration(for: .cordovaNativeStorage)
            } else {
                configuration = PreferencesConfiguration(for: .named(group))
            }
        } else {
            configuration = PreferencesConfiguration()
        }

        preferences = Preferences(with: configuration)
        call.resolve()
    }

    func get(_ call: CAPPluginCall) throws {
        guard let key = call.getString("key") else {
            throw CAPPluginError("Must provide a key")
        }

        let value = preferences.get(by: key)

        call.resolve([
            "value": value as Any
        ])
    }

    func set(_ call: CAPPluginCall) throws {
        guard let key = call.getString("key") else {
            throw CAPPluginError("Must provide a key")
        }
        let value = call.getString("value", "")

        preferences.set(value, for: key)
        call.resolve()
    }

    func remove(_ call: CAPPluginCall) throws {
        guard let key = call.getString("key") else {
            throw CAPPluginError("Must provide a key")
        }

        preferences.remove(by: key)
        call.resolve()
    }

    func keys(_ call: CAPPluginCall) {
        let keys = preferences.keys()

        call.resolve([
            "keys": keys
        ])
    }

    func clear(_ call: CAPPluginCall) {
        preferences.removeAll()
        call.resolve()
    }

    func migrate(_ call: CAPPluginCall) {
        var migrated: [String] = []
        var existing: [String] = []
        let oldPrefix = "_cap_"
        let oldKeys = UserDefaults.standard.dictionaryRepresentation().keys.filter { $0.hasPrefix(oldPrefix) }

        for oldKey in oldKeys {
            let key = String(oldKey.dropFirst(oldPrefix.count))
            let value = UserDefaults.standard.string(forKey: oldKey) ?? ""
            let currentValue = preferences.get(by: key)

            if currentValue == nil {
                preferences.set(value, for: key)
                migrated.append(key)
            } else {
                existing.append(key)
            }
        }

        call.resolve([
            "migrated": migrated,
            "existing": existing
        ])
    }

    func removeOld(_ call: CAPPluginCall) {
        let oldPrefix = "_cap_"
        let oldKeys = UserDefaults.standard.dictionaryRepresentation().keys.filter { $0.hasPrefix(oldPrefix) }
        for oldKey in oldKeys {
            UserDefaults.standard.removeObject(forKey: oldKey)
        }
        call.resolve()
    }
}
