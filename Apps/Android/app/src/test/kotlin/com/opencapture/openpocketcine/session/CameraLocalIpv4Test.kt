package com.opencapture.openpocketcine.session

import com.opencapture.openpocketcine.pairing.CameraApJoiner
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class CameraLocalIpv4Test {
    @Test
    fun associatedIpv4MatchesCameraSoftAP() {
        assertTrue(CameraApJoiner.isAssociatedIPv4("192.168.2.15"))
        assertTrue(CameraApJoiner.isAssociatedIPv4("192.168.2.2"))
        assertTrue(CameraApJoiner.isAssociatedIPv4("192.168.2.254"))
        assertTrue(!CameraApJoiner.isAssociatedIPv4("192.168.2.1"))
        assertTrue(!CameraApJoiner.isAssociatedIPv4("192.168.2.0"))
        assertTrue(!CameraApJoiner.isAssociatedIPv4("192.168.2.255"))
        assertTrue(!CameraApJoiner.isAssociatedIPv4("192.168.1.15"))
        assertTrue(!CameraApJoiner.isAssociatedIPv4("10.0.0.2"))
        assertTrue(!CameraApJoiner.isAssociatedIPv4(""))
        assertTrue(!CameraApJoiner.isAssociatedIPv4("192.168.2"))
    }

    @Test
    fun cameraLocalIpv4PicksAssociatedAddress() {
        assertEquals(
            "192.168.2.15",
            CameraApJoiner.cameraLocalIPv4(
                listOf("192.168.1.20", "192.168.2.15", "127.0.0.1"),
            ),
        )
        assertNull(CameraApJoiner.cameraLocalIPv4(listOf("192.168.1.20", "127.0.0.1")))
        assertNull(CameraApJoiner.cameraLocalIPv4(listOf("192.168.2.1")))
    }

    @Test
    fun udpBindStaysWildcardEphemeralAfterNetworkPin() {
        assertEquals(DatalinkDriver.WILDCARD_BIND_HOST, DatalinkDriver.udpBindHost("192.168.2.15"))
        assertEquals(DatalinkDriver.WILDCARD_BIND_HOST, DatalinkDriver.udpBindHost(null))
        assertEquals(DatalinkDriver.WILDCARD_BIND_HOST, DatalinkDriver.udpBindHost(""))
        // Local :9004 accepted handshake/0x01 and dropped HEVC. iOS/Mimo use
        // an ephemeral client port; camera 9004 is the remote only.
        assertEquals(0, DatalinkDriver.udpBindPort())
    }
}
