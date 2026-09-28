package com.opencapture.openpocketcine.pairing

import android.Manifest
import com.opencapture.openpocketcine.pairing.DiscoveryPermissions.Route
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class DiscoveryPermissionsTest {
    private val scan = Manifest.permission.BLUETOOTH_SCAN
    private val connect = Manifest.permission.BLUETOOTH_CONNECT
    private val fine = Manifest.permission.ACCESS_FINE_LOCATION

    @Test
    fun findingTheCameraAsksOnlyForWhatTheBluetoothScanNeeds() {
        for (sdk in 29..30) {
            assertEquals(listOf(fine), DiscoveryPermissions.discovery(sdk))
            assertTrue(DiscoveryPermissions.discoveryNeedsLocationServices(sdk))
        }
        for (sdk in listOf(31, 32, 33, 36, 37)) {
            assertEquals(listOf(scan, connect), DiscoveryPermissions.discovery(sdk))
            assertFalse(DiscoveryPermissions.discoveryNeedsLocationServices(sdk))
        }
    }

    @Test
    fun wifiNameAsksForPreciseLocationWithCoarseAlongside() {
        assertEquals(listOf(fine), DiscoveryPermissions.wifiName)
        assertTrue(Manifest.permission.ACCESS_COARSE_LOCATION in DiscoveryPermissions.wifiNameRequest)
        assertTrue(fine in DiscoveryPermissions.wifiNameRequest)
    }

    @Test
    fun settingsCopyNamesThePermissionAndroidShows() {
        assertEquals("Nearby devices", DiscoveryPermissions.settingsName(DiscoveryPermissions.discovery(34)))
        assertEquals("Location", DiscoveryPermissions.settingsName(DiscoveryPermissions.discovery(30)))
    }

    @Test
    fun onlyAPermanentDenialRoutesToSettings() {
        val missing = listOf(scan, connect)
        // Never asked: rationale is false, but the dialog still shows.
        assertEquals(Route.REQUEST, DiscoveryPermissions.route(missing, { false }, { false }))
        // Denied once: Android explains and still shows the dialog.
        assertEquals(Route.REQUEST, DiscoveryPermissions.route(missing, { true }, { true }))
        // Denied twice or "Don't ask again": no dialog, only Settings.
        assertEquals(Route.SETTINGS, DiscoveryPermissions.route(missing, { true }, { false }))
        // One blocked permission is enough: the dialog cannot grant it.
        assertEquals(Route.SETTINGS, DiscoveryPermissions.route(missing, { it == connect }, { it != connect }))
        assertEquals(Route.REQUEST, DiscoveryPermissions.route(emptyList(), { true }, { false }))
    }
}
