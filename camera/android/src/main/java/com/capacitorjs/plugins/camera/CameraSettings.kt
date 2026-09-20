package com.capacitorjs.plugins.camera

public class CameraSettings {
    public var resultType: CameraResultType? = CameraResultType.BASE64
    public var quality: Int = DEFAULT_QUALITY

    @get:JvmName("isShouldResize")
    public var shouldResize: Boolean = false

    @get:JvmName("isShouldCorrectOrientation")
    public var shouldCorrectOrientation: Boolean = DEFAULT_CORRECT_ORIENTATION

    @get:JvmName("isSaveToGallery")
    public var saveToGallery: Boolean = DEFAULT_SAVE_IMAGE_TO_GALLERY

    @get:JvmName("isAllowEditing")
    public var allowEditing: Boolean = false
    public var width: Int = 0
    public var height: Int = 0
    public var source: CameraSource = CameraSource.PROMPT

    public companion object {
        public const val DEFAULT_QUALITY: Int = 90
        public const val DEFAULT_SAVE_IMAGE_TO_GALLERY: Boolean = false
        public const val DEFAULT_CORRECT_ORIENTATION: Boolean = true
    }
}
