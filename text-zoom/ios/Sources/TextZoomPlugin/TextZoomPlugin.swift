import Foundation
import Capacitor

@objc(TextZoomPlugin)
public class TextZoomPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "TextZoomPlugin"
    public let jsName = "TextZoom"
    public let pluginMethods: [CAPPluginMethod] = [
        .promise("getPreferred", TextZoomPlugin.getPreferred)
    ]
    private let textZoom = TextZoom()

    func getPreferred(_ call: CAPPluginCall) {
        call.resolve([
            "value": textZoom.preferredFontSize()
        ])
    }
}
