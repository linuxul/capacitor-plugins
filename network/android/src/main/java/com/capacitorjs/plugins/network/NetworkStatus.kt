package com.capacitorjs.plugins.network

public class NetworkStatus {
    public enum class ConnectionType(public val connectionType: String) {
        WIFI("wifi"),
        CELLULAR("cellular"),
        NONE("none"),
        UNKNOWN("unknown")
    }

    @JvmField
    public var connected: Boolean = false

    @JvmField
    public var connectionType: ConnectionType = ConnectionType.NONE
}
