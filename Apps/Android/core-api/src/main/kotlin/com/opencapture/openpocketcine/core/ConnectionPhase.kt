package com.opencapture.openpocketcine.core

/**
 * Operator-visible stage of a Pocket connection. Mirrors Swift
 * `ConnectionPhase` in OpenPocketViewCore: BLE, then Wi-Fi, then datalink.
 * DJI-owned: it moves to an OpenCine Android DJI module with the Kotlin DJI session.
 * Commands and camera state use OpenCineCore (`com.opencapture.opencine.core`), not this module.
 */
public enum class ConnectionPhase {
    IDLE,
    SCANNING,
    CONNECTING_GATT,
    PAIRING,
    AWAITING_APPROVAL,
    READING_WIFI_CREDS,
    JOINING_WIFI,
    OPENING_DATALINK,
    LIVE,
    FAILED,
}
