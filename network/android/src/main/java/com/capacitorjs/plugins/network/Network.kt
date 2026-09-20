package com.capacitorjs.plugins.network

import android.content.Context
import android.net.ConnectivityManager
import android.net.ConnectivityManager.NetworkCallback
import android.net.NetworkCapabilities

public class Network(context: Context) {
    /**
     * Interface for callbacks when network status changes.
     */
    internal fun interface NetworkStatusChangeListener {
        fun onNetworkStatusChanged(wasLostEvent: Boolean)
    }

    internal inner class ConnectivityCallback : NetworkCallback() {
        override fun onLost(network: android.net.Network) {
            super.onLost(network)
            statusChangeListener?.onNetworkStatusChanged(true)
        }

        override fun onCapabilitiesChanged(network: android.net.Network, networkCapabilities: NetworkCapabilities) {
            super.onCapabilitiesChanged(network, networkCapabilities)
            statusChangeListener?.onNetworkStatusChanged(false)
        }
    }

    /**
     * The object that receives callbacks.
     */
    internal var statusChangeListener: NetworkStatusChangeListener? = null

    private val connectivityCallback = ConnectivityCallback()
    private val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager

    /**
     * Get the current network information.
     * @return NetworkStatus
     */
    public fun getNetworkStatus(): NetworkStatus {
        val networkStatus = NetworkStatus()
        val connectivityManager = connectivityManager ?: return networkStatus
        val activeNetwork = connectivityManager.activeNetwork
        val capabilities = connectivityManager.getNetworkCapabilities(connectivityManager.activeNetwork)
        if (activeNetwork != null && capabilities != null) {
            networkStatus.connected =
                capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) &&
                capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            networkStatus.connectionType =
                when {
                    capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> NetworkStatus.ConnectionType.WIFI
                    capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> NetworkStatus.ConnectionType.CELLULAR
                    else -> NetworkStatus.ConnectionType.UNKNOWN
                }
        }
        return networkStatus
    }

    /**
     * Register a network callback.
     */
    public fun startMonitoring() {
        connectivityManager?.registerDefaultNetworkCallback(connectivityCallback)
    }

    /**
     * Unregister the network callback.
     */
    public fun stopMonitoring() {
        connectivityManager?.unregisterNetworkCallback(connectivityCallback)
    }
}
