package com.example.excel_app

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.net.Inet4Address

class MainActivity: FlutterActivity() {
    private val networkChannel = "com.example.excel_app/network"

    /// Registers the small native bridge used to read the active LAN address.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, networkChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "getWifiIp") {
                    result.success(getWifiIp())
                } else {
                    result.notImplemented()
                }
            }
    }

    /// Returns an IPv4 address from Wi-Fi or Ethernet without scanning all interfaces.
    private fun getWifiIp(): String? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val connectivity =
                    getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                connectivity.allNetworks.asSequence()
                    .mapNotNull { network ->
                        val capabilities = connectivity.getNetworkCapabilities(network)
                            ?: return@mapNotNull null
                        val isLan = capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
                            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
                        if (!isLan) return@mapNotNull null
                        connectivity.getLinkProperties(network)
                            ?.linkAddresses
                            ?.mapNotNull { linkAddress ->
                                linkAddress.address as? Inet4Address
                            }
                            ?.firstOrNull { !it.isLoopbackAddress && !it.isLinkLocalAddress }
                    }
                    .firstOrNull()
                    ?.hostAddress
            } else {
                val wifiManager =
                    applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
                val ip = wifiManager?.connectionInfo?.ipAddress ?: 0
                if (ip == 0) null else formatIpv4(ip)
            }
        } catch (_: SecurityException) {
            null
        } catch (_: Exception) {
            null
        }
    }

    /// Converts Android's little-endian Wi-Fi integer address to dotted IPv4.
    private fun formatIpv4(ip: Int): String {
        return "${ip and 0xff}.${ip shr 8 and 0xff}.${ip shr 16 and 0xff}.${ip shr 24 and 0xff}"
    }
}
