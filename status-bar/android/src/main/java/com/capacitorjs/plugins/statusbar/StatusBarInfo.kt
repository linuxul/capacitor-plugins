package com.capacitorjs.plugins.statusbar

import java.io.Serializable

// The property names are the serialized field names, so the Boolean ones cannot take the "is" prefix
public class StatusBarInfo : Serializable {
    @get:JvmName("isOverlays")
    public var overlays: Boolean = false

    @get:JvmName("isVisible")
    public var visible: Boolean = false
    public var style: String? = null
    public var color: String? = null
    public var height: Int = 0
}
