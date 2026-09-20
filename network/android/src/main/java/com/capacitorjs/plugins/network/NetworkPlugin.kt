package com.capacitorjs.plugins.network

import android.util.Log
import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin

@CapacitorPlugin(name = "Network")
public class NetworkPlugin : Plugin() {
    private lateinit var implementation: Network
    private var prePauseNetworkStatus: NetworkStatus? = null

    /**
     * Monitor for network status changes and fire our event.
     */
    override fun load() {
        implementation = Network(context)
        implementation.statusChangeListener =
            Network.NetworkStatusChangeListener { wasLostEvent ->
                if (wasLostEvent) {
                    val jsObject = JSObject()
                    jsObject.put("connected", false)
                    jsObject.put("connectionType", "none")
                    notifyListeners(NETWORK_CHANGE_EVENT, jsObject)
                } else {
                    updateNetworkStatus()
                }
            }
    }

    /**
     * Clean up callback to prevent leaks.
     */
    override fun handleOnDestroy() {
        implementation.statusChangeListener = null
    }

    /**
     * Get current network status information.
     * @param call
     */
    @PluginMethod
    public fun getStatus(call: PluginCall) {
        call.resolve(parseNetworkStatus(implementation.getNetworkStatus()))
    }

    /**
     * Register the network callback on resume
     */
    override fun handleOnResume() {
        implementation.startMonitoring()
        val afterPauseNetworkStatus = implementation.getNetworkStatus()
        val prePauseNetworkStatus = prePauseNetworkStatus
        if (prePauseNetworkStatus != null &&
            !afterPauseNetworkStatus.connected &&
            (prePauseNetworkStatus.connected || afterPauseNetworkStatus.connectionType != prePauseNetworkStatus.connectionType)
        ) {
            Log.d(
                "Capacitor/NetworkPlugin",
                "Detected pre-pause and after-pause network status mismatch. Updating network status and notifying listeners."
            )
            updateNetworkStatus()
        }
        this.prePauseNetworkStatus = null
    }

    /**
     * Unregister the network callback on pause to avoid leaking it
     */
    override fun handleOnPause() {
        prePauseNetworkStatus = implementation.getNetworkStatus()
        implementation.stopMonitoring()
    }

    private fun updateNetworkStatus() {
        notifyListeners(NETWORK_CHANGE_EVENT, parseNetworkStatus(implementation.getNetworkStatus()))
    }

    private fun parseNetworkStatus(networkStatus: NetworkStatus): JSObject {
        val jsObject = JSObject()
        jsObject.put("connected", networkStatus.connected)
        jsObject.put("connectionType", networkStatus.connectionType.connectionType)
        return jsObject
    }

    public companion object {
        public const val NETWORK_CHANGE_EVENT: String = "networkStatusChange"
    }
}
