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
        .async("getPhoto", CameraPlugin.getPhoto),
        .async("pickImages", CameraPlugin.pickImages),
        .promise("checkPermissions", CameraPlugin.checkPermissions),
        .async("requestPermissions", CameraPlugin.requestCameraPermissions),
        .async("pickLimitedLibraryPhotos", CameraPlugin.pickLimitedLibraryPhotos),
        .async("getLimitedLibraryPhotos", CameraPlugin.getLimitedLibraryPhotos)
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

    /// Reading the authorization statuses is thread-safe: the method stays synchronous.
    override public func checkPermissions(_ call: CAPPluginCall) {
        call.resolve(CameraPlugin.permissionStates())
    }

    /// The permission state of every permission type, as checkPermissions and requestPermissions resolve with it.
    static func permissionStates() -> JSObject {
        var result: JSObject = [:]
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
        return result
    }

    /// Requests the permissions the call names, or all of them, one after the other, and returns the states. It is
    /// registered as requestPermissions: an async method cannot override the synchronous CAPPlugin method.
    func requestCameraPermissions(_ call: CAPPluginCall) async -> JSObject {
        // get the list of desired types, if passed
        let typeList = call.getArray("permissions", String.self)?.compactMap({ (type) -> CameraPermissionType? in
            return CameraPermissionType(rawValue: type)
        }) ?? []
        // otherwise check everything
        let permissions: [CameraPermissionType] = (typeList.count > 0) ? typeList : CameraPermissionType.allCases
        // request the permissions
        for permission in permissions {
            switch permission {
            case .camera:
                _ = await AVCaptureDevice.requestAccess(for: .video)
            case .photos:
                _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            }
        }
        return CameraPlugin.permissionStates()
    }

    /// Lets the user change the limited library selection, then returns its photos. The picker is UIKit: the method
    /// runs on the main actor.
    @MainActor
    func pickLimitedLibraryPhotos(_ call: CAPPluginCall) async throws -> JSObject {
        guard await PHPhotoLibrary.requestAuthorization(for: .readWrite) == .limited else {
            return [
                "photos": [JSObject]()
            ]
        }
        guard let presenter = CameraPlugin.topmostPresenter(from: bridge?.viewController) else {
            throw CAPPluginError(CameraPlugin.noPresenterMessage)
        }
        _ = await PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: presenter)
        return try await limitedLibraryPhotos()
    }

    /// This call takes no options and has nothing to do with a getPhoto or pickImages call in progress: it uses the
    /// default settings and answers itself, not the active call.
    func getLimitedLibraryPhotos(_ call: CAPPluginCall) async throws -> JSObject {
        guard await PHPhotoLibrary.requestAuthorization(for: .readWrite) == .limited else {
            return [
                "photos": [JSObject]()
            ]
        }
        return try await limitedLibraryPhotos()
    }

    /// Every photo of the limited library, processed with the default settings and saved as temporary files.
    private func limitedLibraryPhotos() async throws -> JSObject {
        return try await withCheckedContinuation { (continuation: CheckedContinuation<Result<JSObject, Error>, Never>) in
            loadLimitedLibraryPhotos { continuation.resume(returning: $0) }
        }.get()
    }

    /// Loads and encodes every photo of the limited library on a utility queue, not in the Swift concurrency pool, and
    /// calls `completion` once with the `{ photos }` result or the error that kept a photo from being saved.
    private func loadLimitedLibraryPhotos(_ completion: @escaping (Result<JSObject, Error>) -> Void) {
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
                let images = imagesLock.withLock { processedImages }
                completion(Result { try self.photosResult(images, jpegQuality: settings.jpegQuality) })
            }
        }
    }

    /// Shows the source prompt, the camera or the photo picker, and returns the photo once a picker path ends the call.
    @MainActor
    func getPhoto(_ call: CAPPluginCall) async throws -> JSObject {
        // Make sure they have all the necessary info.plist settings
        if let missingUsageDescription = checkUsageDescriptions() {
            CAPLog.print("⚡️ ", self.pluginId, "-", missingUsageDescription)
            throw CAPPluginError(missingUsageDescription)
        }
        return try await whileActive(call, multiple: false) {
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

    /// Shows the photo picker and returns `{ photos }` once a picker path ends the call.
    @MainActor
    func pickImages(_ call: CAPPluginCall) async throws -> JSObject {
        return try await whileActive(call, multiple: true) {
            self.showPhotos()
        }
    }

    /// Makes `call` the active call, runs `show` to put its picker on screen, and returns what the picker path that
    /// ends the call answers. A call made while another is in progress throws, and leaves the active call alone.
    ///
    /// The answer is resumed exactly once: `ActiveCall.finish(with:)` hands it to the first path that ends the call
    /// only, and the slot answers a call it still holds when it goes away with the plugin.
    @MainActor
    func whileActive(_ call: CAPPluginCall, multiple: Bool, show: () -> Void) async throws -> JSObject {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<JSObject, Error>) in
            guard activeCall.begin(call, answer: { continuation.resume(with: $0) }) else {
                continuation.resume(throwing: CAPPluginError(CameraPlugin.callInProgressMessage))
                return
            }
            self.multiple = multiple
            self.settings = cameraSettings(from: call)
            show()
        }
    }

    /// Ends the active call with `result` and frees the slot for the next one.
    func finishActiveCall(_ result: Result<JSObject, Error>) {
        activeCall.finish(with: result)
    }

    /// Resolves the active call and frees the slot for the next one.
    func resolveActiveCall(_ data: JSObject) {
        finishActiveCall(.success(data))
    }

    /// Rejects the active call and frees the slot for the next one.
    func rejectActiveCall(_ message: String) {
        finishActiveCall(.failure(CAPPluginError(message)))
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
