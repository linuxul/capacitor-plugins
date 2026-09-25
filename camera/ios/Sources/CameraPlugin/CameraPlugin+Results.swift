import Foundation
import Capacitor
import UIKit
import Photos

// Turning picked images into call results.
extension CameraPlugin {
    func returnImage(_ processedImage: ProcessedImage, isSaved: Bool) {
        guard let jpeg = processedImage.generateJPEG(with: settings.jpegQuality) else {
            rejectActiveCall("Unable to convert image to jpeg")
            return
        }

        switch settings.resultType {
        case .uri:
            guard let fileURL = try? saveTemporaryImage(jpeg),
                  let webURL = bridge?.portablePath(fromLocalURL: fileURL) else {
                rejectActiveCall("Unable to get portable path to file")
                return
            }
            resolveActiveCall([
                "path": fileURL.absoluteString,
                "exif": processedImage.exifData,
                "webPath": webURL.absoluteString,
                "format": "jpeg",
                "saved": isSaved
            ])
        case .base64:
            resolveActiveCall([
                "base64String": jpeg.base64EncodedString(),
                "exif": processedImage.exifData,
                "format": "jpeg",
                "saved": isSaved
            ])
        case .dataURL:
            resolveActiveCall([
                "dataUrl": "data:image/jpeg;base64," + jpeg.base64EncodedString(),
                "exif": processedImage.exifData,
                "format": "jpeg",
                "saved": isSaved
            ])
        }
    }

    /// Saves `processedImages` as temporary JPEG files and resolves `call` with them, or rejects it when one fails.
    /// `call` is the active pickImages call, or a getLimitedLibraryPhotos call that never occupies the slot.
    func returnImages(_ processedImages: [ProcessedImage], jpegQuality: CGFloat, to call: CAPPluginCall?) {
        var photos: [PluginCallResultData] = []
        for processedImage in processedImages {
            guard let jpeg = processedImage.generateJPEG(with: jpegQuality) else {
                call?.reject("Unable to convert image to jpeg")
                return
            }

            guard let fileURL = try? saveTemporaryImage(jpeg),
                  let webURL = bridge?.portablePath(fromLocalURL: fileURL) else {
                call?.reject("Unable to get portable path to file")
                return
            }

            photos.append([
                "path": fileURL.absoluteString,
                "exif": processedImage.exifData,
                "webPath": webURL.absoluteString,
                "format": "jpeg"
            ])
        }
        call?.resolve([
            "photos": photos
        ])
    }

    func returnProcessedImage(_ processedImage: ProcessedImage) {
        // conditionally save the image
        if settings.saveToGallery && (processedImage.flags.contains(.edited) == true || processedImage.flags.contains(.gallery) == false) {
            _ = ImageSaver(image: processedImage.image) { error in
                var isSaved = false
                if error == nil {
                    isSaved = true
                }
                self.returnImage(processedImage, isSaved: isSaved)
            }
        } else {
            self.returnImage(processedImage, isSaved: false)
        }
    }

    func saveTemporaryImage(_ data: Data) throws -> URL {
        let url = nextTemporaryImageURL()
        try data.write(to: url, options: .atomic)
        return url
    }

    func processImage(from info: [UIImagePickerController.InfoKey: Any]) -> ProcessedImage? {
        var selectedImage: UIImage?
        var flags: PhotoFlags = []
        // get the image
        if let edited = info[UIImagePickerController.InfoKey.editedImage] as? UIImage {
            selectedImage = edited // use the edited version
            flags = flags.union([.edited])
        } else if let original = info[UIImagePickerController.InfoKey.originalImage] as? UIImage {
            selectedImage = original // use the original version
        }
        guard let image = selectedImage else {
            return nil
        }
        var metadata: [String: Any] = [:]
        // get the image's metadata from the picker or from the photo album
        if let photoMetadata = info[UIImagePickerController.InfoKey.mediaMetadata] as? [String: Any] {
            metadata = photoMetadata
        } else {
            flags = flags.union([.gallery])
        }
        if let asset = info[UIImagePickerController.InfoKey.phAsset] as? PHAsset {
            metadata = asset.imageData
        }
        // get the result
        var result = processedImage(from: image, with: metadata, settings: settings)
        result.flags = flags
        return result
    }

    func processedImage(from image: UIImage, with metadata: [String: Any]?, settings: CameraSettings) -> ProcessedImage {
        var result = ProcessedImage(image: image, metadata: metadata ?? [:])
        // resizing the image only makes sense if we have real values to which to constrain it
        if settings.shouldResize, settings.width > 0 || settings.height > 0 {
            result.image = result.image.reformat(to: CGSize(width: settings.width, height: settings.height))
            result.overwriteMetadataOrientation(to: 1)
        } else if settings.shouldCorrectOrientation {
            // resizing implicitly reformats the image so this is only needed if we aren't resizing
            result.image = result.image.reformat()
            result.overwriteMetadataOrientation(to: 1)
        }
        return result
    }
}
