import Foundation
import Capacitor
import UIKit
import Photos
import PhotosUI

@objc(CAPCameraPlugin)
public class CameraPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "CAPCameraPlugin"
    public let jsName = "Camera"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "getPhoto", returnType: .promise),
        CAPPluginMethod(name: "pickImages", returnType: .promise),
        CAPPluginMethod(name: "checkPermissions", returnType: .promise),
        CAPPluginMethod(name: "requestPermissions", returnType: .promise),
        CAPPluginMethod(name: "pickLimitedLibraryPhotos", returnType: .promise),
        CAPPluginMethod(name: "getLimitedLibraryPhotos", returnType: .promise)
    ]
    static let callInProgressMessage = "Another getPhoto or pickImages call is in progress"
    static let noPresenterMessage = "Unable to display the picker: there is no view controller to present it from"

    /// The getPhoto or pickImages call the picker on screen works for. `settings` and `multiple` belong to it and are
    /// only written while no call is active.
    let activeCall = ActiveCall()
    var settings = CameraSettings()
    var multiple = false
    private let defaultSource = CameraSource.prompt
    private let defaultDirection = CameraDirection.rear

    private let imageCounterLock = NSLock()
    private var imageCounter = 0

    @objc override public func checkPermissions(_ call: CAPPluginCall) {
        var result: [String: Any] = [:]
        for permission in CameraPermissionType.allCases {
            let state: String
            switch permission {
            case .camera:
                state = AVCaptureDevice.authorizationStatus(for: .video).authorizationState
            case .photos:
                state = PHPhotoLibrary.authorizationStatus(for: .readWrite).authorizationState
            }
            result[permission.rawValue] = state
        }
        call.resolve(result)
    }

    @objc override public func requestPermissions(_ call: CAPPluginCall) {
        // get the list of desired types, if passed
        let typeList = call.getArray("permissions", String.self)?.compactMap({ (type) -> CameraPermissionType? in
            return CameraPermissionType(rawValue: type)
        }) ?? []
        // otherwise check everything
        let permissions: [CameraPermissionType] = (typeList.count > 0) ? typeList : CameraPermissionType.allCases
        // request the permissions
        let group = DispatchGroup()
        for permission in permissions {
            switch permission {
            case .camera:
                group.enter()
                AVCaptureDevice.requestAccess(for: .video) { _ in
                    group.leave()
                }
            case .photos:
                group.enter()
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { (_) in
                    group.leave()
                }
            }
        }
        group.notify(queue: DispatchQueue.main) { [weak self] in
            self?.checkPermissions(call)
        }
    }

    @objc func pickLimitedLibraryPhotos(_ call: CAPPluginCall) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] (granted) in
            guard granted == .limited else {
                call.resolve([
                    "photos": []
                ])
                return
            }
            // Photos calls back on a background queue; the limited library picker is UIKit.
            DispatchQueue.main.async {
                guard let self, let presenter = CameraPlugin.topmostPresenter(from: self.bridge?.viewController) else {
                    call.reject(CameraPlugin.noPresenterMessage)
                    return
                }
                PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: presenter) { [weak self] _ in
                    guard let self else {
                        call.reject("The camera plugin is no longer available")
                        return
                    }
                    self.getLimitedLibraryPhotos(call)
                }
            }
        }
    }

    @objc func getLimitedLibraryPhotos(_ call: CAPPluginCall) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] (granted) in
            guard granted == .limited else {
                call.resolve([
                    "photos": []
                ])
                return
            }
            guard let self else {
                call.reject("The camera plugin is no longer available")
                return
            }
            // This call takes no options and has nothing to do with a getPhoto or pickImages call in progress, so it
            // uses the default settings and settles `call` directly, not the active call.
            let settings = CameraSettings()
            DispatchQueue.global(qos: .utility).async {
                let assets = PHAsset.fetchAssets(with: .image, options: nil)
                let imagesLock = NSLock()
                var processedImages: [ProcessedImage] = []

                let imageManager = PHImageManager.default()
                let options = PHImageRequestOptions()
                options.deliveryMode = .highQualityFormat

                let group = DispatchGroup()
                assets.enumerateObjects { asset, _, _ in
                    let fullSize = CGSize(width: asset.pixelWidth, height: asset.pixelHeight)

                    group.enter()
                    imageManager.requestImage(for: asset, targetSize: fullSize, contentMode: .default, options: options) { image, _ in
                        if let image {
                            let processedImage = self.processedImage(from: image, with: asset.imageData, settings: settings)
                            imagesLock.withLock {
                                processedImages.append(processedImage)
                            }
                        }
                        group.leave()
                    }
                }

                group.notify(queue: .global(qos: .utility)) {
                    self.returnImages(imagesLock.withLock { processedImages }, jpegQuality: settings.jpegQuality, to: call)
                }
            }
        }
    }

    @objc func getPhoto(_ call: CAPPluginCall) {
        // Make sure they have all the necessary info.plist settings
        if let missingUsageDescription = checkUsageDescriptions() {
            CAPLog.print("⚡️ ", self.pluginId, "-", missingUsageDescription)
            call.reject(missingUsageDescription)
            return
        }
        guard activeCall.begin(call) else {
            call.reject(CameraPlugin.callInProgressMessage)
            return
        }
        self.multiple = false
        self.settings = cameraSettings(from: call)

        DispatchQueue.main.async {
            switch self.settings.source {
            case .prompt:
                self.showPrompt()
            case .camera:
                self.showCamera()
            case .photos:
                self.showPhotos()
            }
        }
    }

    @objc func pickImages(_ call: CAPPluginCall) {
        guard activeCall.begin(call) else {
            call.reject(CameraPlugin.callInProgressMessage)
            return
        }
        self.multiple = true
        self.settings = cameraSettings(from: call)
        DispatchQueue.main.async {
            self.showPhotos()
        }
    }

    /// Resolves the active call and frees the slot for the next one.
    func resolveActiveCall(_ data: PluginCallResultData) {
        activeCall.take()?.resolve(data)
    }

    /// Rejects the active call and frees the slot for the next one.
    func rejectActiveCall(_ message: String) {
        activeCall.take()?.reject(message)
    }

    /// The next file name for a temporary photo. Pickers and getLimitedLibraryPhotos save from different queues.
    func nextTemporaryImageURL() -> URL {
        return imageCounterLock.withLock {
            var url: URL
            repeat {
                imageCounter += 1
                url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("photo-\(imageCounter).jpg")
            } while FileManager.default.fileExists(atPath: url.path)
            return url
        }
    }

    private func checkUsageDescriptions() -> String? {
        if let dict = Bundle.main.infoDictionary {
            for key in CameraPropertyListKeys.allCases where dict[key.rawValue] == nil {
                return key.missingMessage
            }
        }
        return nil
    }

    private func cameraSettings(from call: CAPPluginCall) -> CameraSettings {
        var settings = CameraSettings()
        settings.jpegQuality = min(abs(CGFloat(call.getFloat("quality") ?? 100.0)) / 100.0, 1.0)
        settings.allowEditing = call.getBool("allowEditing") ?? false
        settings.source = CameraSource(rawValue: call.getString("source") ?? defaultSource.rawValue) ?? defaultSource
        settings.direction = CameraDirection(rawValue: call.getString("direction") ?? defaultDirection.rawValue) ?? defaultDirection
        if let typeString = call.getString("resultType"), let type = CameraResultType(rawValue: typeString) {
            settings.resultType = type
        }
        settings.saveToGallery = call.getBool("saveToGallery") ?? false

        // Get the new image dimensions if provided
        settings.width = CGFloat(call.getInt("width") ?? 0)
        settings.height = CGFloat(call.getInt("height") ?? 0)
        if settings.width > 0 || settings.height > 0 {
            // We resize only if a dimension was provided
            settings.shouldResize = true
        }
        settings.shouldCorrectOrientation = call.getBool("correctOrientation") ?? true
        settings.userPromptText = CameraPromptText(title: call.getString("promptLabelHeader"),
                                                   photoAction: call.getString("promptLabelPhoto"),
                                                   cameraAction: call.getString("promptLabelPicture"),
                                                   cancelAction: call.getString("promptLabelCancel"))
        if let styleString = call.getString("presentationStyle"), styleString == "popover" {
            settings.presentationStyle = .popover
        } else {
            settings.presentationStyle = .fullScreen
        }

        return settings
    }
}

extension CameraPlugin {
    /// The view controller to present from: the last controller in the chain presented over `root`, skipping one that
    /// is being dismissed (the prompt, once an option is chosen). Presenting from `root` itself while it already
    /// presents a controller fails silently, which left the call pending when the app showed a modal over the web
    /// view. Call on the main thread.
    static func topmostPresenter(from root: UIViewController?) -> UIViewController? {
        var presenter = root
        while let presented = presenter?.presentedViewController, !presented.isBeingDismissed {
            presenter = presented
        }
        return presenter
    }

    /// Centers the popover of `controller` on the view of `presenter`, without an arrow. The anchor has to be in the
    /// presenter's hierarchy, which the bridge view controller's view is not when a full-screen modal covers it.
    /// Call on the main thread.
    static func centerPopover(_ controller: UIViewController, on presenter: UIViewController) {
        guard let popover = controller.popoverPresentationController, let view = presenter.view else {
            return
        }
        popover.sourceView = view
        popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        popover.permittedArrowDirections = []
    }
}
