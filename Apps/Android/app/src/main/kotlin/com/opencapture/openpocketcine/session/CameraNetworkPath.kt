package com.opencapture.openpocketcine.session

import java.net.DatagramSocket
import java.net.Socket

/**
 * The network one datalink runs on: the camera SoftAP ([com.opencapture.openpocketcine.pairing.CameraApJoiner])
 * or the Multiview shared Wi-Fi. iOS `DatalinkDriver.pathReady` / `cameraParameters`.
 */
interface CameraNetworkPath {
    fun bindSocket(socket: DatagramSocket)
    fun bindSocket(socket: Socket)
    fun isProcessBound(): Boolean
    fun cameraLocalIPv4(): String?
}
