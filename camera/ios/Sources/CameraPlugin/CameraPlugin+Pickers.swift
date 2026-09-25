import Foundation
import Capacitor
import UIKit
import Photos
import PhotosUI

// Every picker path ends in resolveActiveCall or rejectActiveCall, which free the slot for the next getPhoto or
// pickImages call. A path that did not would leave every later call rejected as "in progress".

// public delegate methods
extension CameraPlugin: UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIPopoverPresentationControllerDelegate {
    public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        rejectActiveCall("User cancelled photos app")
    }

    public func popoverPresentationControllerDidDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) {
        rejectActiveCall("User cancelled photos app")
    }

    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        rejectActiveCall("User cancelled photos app")
    }

    public func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true) {
            if let processedImage = self.processImage(from: info) {
                self.returnProcessedImage(processedImage)
            } else {
                self.rejectActiveCall("Error processing image")
            }
        }
    }
}

extension CameraPlugin: PHPickerViewControllerDelegate {
    public func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true, completion: nil)

        guard !results.isEmpty else {
            rejectActiveCall("User cancelled photos app")
            return
        }

        self.fetchProcessedImages(from: results) { [weak self] processedImageArray in
            guard let self else {
                return
            }
            guard let processedImageArray else {
                self.rejectActiveCall("Error loading image")
                return
            }

            if self.multiple {
                self.returnImages(processedImageArray, jpegQuality: self.settings.jpegQuality, to: self.activeCall.take())
            } else if var processedImage = processedImageArray.first {
                processedImage.flags = .gallery
                self.returnProcessedImage(processedImage)
            } else {
                self.rejectActiveCall("Error loading image")
            }
        }
    }

    private func fetchProcessedImages(from pickerResultArray: [PHPickerResult], accumulating: [ProcessedImage] = [], _ completionHandler: @escaping ([ProcessedImage]?) -> Void) {
        func loadImage(from pickerResult: PHPickerResult, _ completionHandler: @escaping (UIImage?) -> Void) {
            let itemProvider = pickerResult.itemProvider
            if itemProvider.canLoadObject(ofClass: UIImage.self) {
                // extract the image
                itemProvider.loadObject(ofClass: UIImage.self) { itemProviderReading, _ in
                    completionHandler(itemProviderReading as? UIImage)
                }
            } else {
                // extract the image's data representation
                itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data else {
                        return completionHandler(nil)
                    }
                    completionHandler(UIImage(data: data))
                }
            }
        }

        guard let currentPickerResult = pickerResultArray.first else { return completionHandler(accumulating) }

        loadImage(from: currentPickerResult) { [weak self] loadedImage in
            guard let self, let loadedImage else { return completionHandler(nil) }
            var asset: PHAsset?
            if let assetId = currentPickerResult.assetIdentifier {
                asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil).firstObject
            }
            let newElement = self.processedImage(from: loadedImage, with: asset?.imageData, settings: self.settings)
            self.fetchProcessedImages(
                from: Array(pickerResultArray.dropFirst()),
                accumulating: accumulating + [newElement],
                completionHandler
            )
        }
    }
}

// Presentation. These run on the main thread.
extension CameraPlugin {
    func showPrompt() {
        guard let presenter = CameraPlugin.topmostPresenter(from: bridge?.viewController) else {
            rejectActiveCall(CameraPlugin.noPresenterMessage)
            return
        }
        // Build the action sheet
        let alert = UIAlertController(title: settings.userPromptText.title, message: nil, preferredStyle: UIAlertController.Style.actionSheet)
        alert.addAction(UIAlertAction(title: settings.userPromptText.photoAction, style: .default, handler: { [weak self] (_: UIAlertAction) in
            self?.showPhotos()
        }))

        alert.addAction(UIAlertAction(title: settings.userPromptText.cameraAction, style: .default, handler: { [weak self] (_: UIAlertAction) in
            self?.showCamera()
        }))

        alert.addAction(UIAlertAction(title: settings.userPromptText.cancelAction, style: .cancel, handler: { [weak self] (_: UIAlertAction) in
            self?.rejectActiveCall("User cancelled photos app")
        }))
        CameraPlugin.centerPopover(alert, on: presenter)
        present(alert, from: presenter)
    }

    func showCamera() {
        // check if we have a camera
        if (bridge?.isSimEnvironment ?? false) || !UIImagePickerController.isSourceTypeAvailable(UIImagePickerController.SourceType.camera) {
            CAPLog.print("⚡️ ", self.pluginId, "-", "Camera not available in simulator")
            rejectActiveCall("Camera not available while running in Simulator")
            return
        }
        // check for permission
        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if authStatus == .restricted || authStatus == .denied {
            rejectActiveCall("User denied access to camera")
            return
        }
        // we either already have permission or can prompt
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            if granted {
                DispatchQueue.main.async {
                    self?.presentCameraPicker()
                }
            } else {
                self?.rejectActiveCall("User denied access to camera")
            }
        }
    }

    func showPhotos() {
        // check for permission
        let authStatus = PHPhotoLibrary.authorizationStatus()
        if authStatus == .restricted || authStatus == .denied {
            rejectActiveCall("User denied access to photos")
            return
        }
        // we either already have permission or can prompt
        if authStatus == .authorized {
            presentPhotoPicker()
        } else {
            PHPhotoLibrary.requestAuthorization({ [weak self] (status) in
                if status == PHAuthorizationStatus.authorized {
                    DispatchQueue.main.async { [weak self] in
                        self?.presentPhotoPicker()
                    }
                } else {
                    self?.rejectActiveCall("User denied access to photos")
                }
            })
        }
    }

    func presentCameraPicker() {
        guard let presenter = CameraPlugin.topmostPresenter(from: bridge?.viewController) else {
            rejectActiveCall(CameraPlugin.noPresenterMessage)
            return
        }
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.allowsEditing = self.settings.allowEditing
        // select the input
        picker.sourceType = .camera
        if settings.direction == .rear, UIImagePickerController.isCameraDeviceAvailable(.rear) {
            picker.cameraDevice = .rear
        } else if settings.direction == .front, UIImagePickerController.isCameraDeviceAvailable(.front) {
            picker.cameraDevice = .front
        }
        presentPicker(picker, from: presenter)
    }

    func presentPhotoPicker() {
        guard let presenter = CameraPlugin.topmostPresenter(from: bridge?.viewController) else {
            rejectActiveCall(CameraPlugin.noPresenterMessage)
            return
        }
        var configuration = PHPickerConfiguration(photoLibrary: PHPhotoLibrary.shared())
        configuration.selectionLimit = self.multiple ? (activeCall.current?.getInt("limit") ?? 0) : 1
        configuration.filter = .images
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        presentPicker(picker, from: presenter)
    }

    private func presentPicker(_ picker: UIViewController, from presenter: UIViewController) {
        picker.modalPresentationStyle = settings.presentationStyle
        if settings.presentationStyle == .popover {
            picker.popoverPresentationController?.delegate = self
            CameraPlugin.centerPopover(picker, on: presenter)
        }
        present(picker, from: presenter)
    }

    /// Presents `controller`, or rejects the active call when UIKit refuses to (it logs and does nothing when the
    /// presenter is mid-transition or its view is not in a window). UIKit sets `presentedViewController` as soon as it
    /// accepts a presentation. Without the check the call, and with it the slot, would stay pending.
    private func present(_ controller: UIViewController, from presenter: UIViewController) {
        presenter.present(controller, animated: true, completion: nil)
        if presenter.presentedViewController !== controller {
            rejectActiveCall(CameraPlugin.noPresenterMessage)
        }
    }
}
