import Foundation
import Capacitor
import UIKit
import Photos

// Turning picked images into call results.
extension CameraPlugin {
    /// Ends the active call with `processedImage`, or with the error that kept it from being returned.
    func returnImage(_ processedImage: ProcessedImage, isSaved: Bool) {
        finishActiveCall(Result { try imageResult(processedImage, isSaved: isSaved) })
    }

    /// The getPhoto result for `processedImage`, in the result type the settings ask for.
    func imageResult(_ processedImage: ProcessedImage, isSaved: Bool) throws -> JSObject {
        guard let jpeg = processedImage.generateJPEG(with: settings.jpegQuality) else {
            throw CAPPluginError("Unable to convert image to jpeg")
        }

        switch settings.resultType {
        case .uri:
            guard let fileURL = try? saveTemporaryImage(jpeg),
                  let webURL = bridge?.portablePath(fromLocalURL: fileURL) else {
                throw CAPPluginError("Unable to get portable path to file")
            }
            return [
                "path": fileURL.absoluteString,
                "exif": processedImage.exifObject,
                "webPath": webURL.absoluteString,
                "format": "jpeg",
                "saved": isSaved
            ]
        case .base64:
            return [
                "base64String": jpeg.base64EncodedString(),
                "exif": processedImage.exifObject,
                "format": "jpeg",
                "saved": isSaved
            ]
        case .dataURL:
            return [
                "dataUrl": "data:image/jpeg;base64," + jpeg.base64EncodedString(),
                "exif": processedImage.exifObject,
                "format": "jpeg",
                "saved": isSaved
            ]
        }
    }

    /// The `{ photos }` result for `processedImages`, saved as temporary JPEG files, for the active pickImages call or
    /// a getLimitedLibraryPhotos call. Throws when an image cannot be encoded or saved.
    func photosResult(_ processedImages: [ProcessedImage], jpegQuality: CGFloat) throws -> JSObject {
        var photos: [JSObject] = []
        for processedImage in processedImages {
            guard let jpeg = processedImage.generateJPEG(with: jpegQuality) else {
                throw CAPPluginError("Unable to convert image to jpeg")
            }

            guard let fileURL = try? saveTemporaryImage(jpeg),
                  let webURL = bridge?.portablePath(fromLocalURL: fileURL) else {
                throw CAPPluginError("Unable to get portable path to file")
            }

            photos.append([
                "path": fileURL.absoluteString,
                "exif": processedImage.exifObject,
                "webPath": webURL.absoluteString,
                "format": "jpeg"
            ])
        }
        return [
            "photos": photos
        ]
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
