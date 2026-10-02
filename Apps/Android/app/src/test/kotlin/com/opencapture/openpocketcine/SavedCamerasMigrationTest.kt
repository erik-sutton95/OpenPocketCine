package com.opencapture.openpocketcine

import com.opencapture.opencine.appkit.SavedCamerasStore
import com.opencapture.opencine.appkit.StoredString
import com.opencapture.opencine.core.CameraDeviceID
import com.opencapture.opencine.core.RouteKind
import com.opencapture.opencine.core.SavedCamera
import com.opencapture.opencine.dji.DjiCameraSessionAdapter
import com.opencapture.opencine.dji.DjiIntegration
import org.json.JSONArray
import org.json.JSONObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * The saved-camera migration of this app (SHELL-02 design 4, tests 1-6) through the store the app
 * builds ([AppModel.camerasStore]), over golden legacy records the shipping encoder wrote
 * (`src/test/resources/saved-cameras`, from `SharedPreferencesSavedCameraStore.encode` before it
 * was deleted). The iOS twin is `DJISavedCamerasMigrationTests`.
 */
class SavedCamerasMigrationTest {
    private class Prefs(vararg seed: Pair<String, String>) {
        val values = mutableMapOf(*seed)
        val writes = mutableListOf<String>()
        fun at(key: String) = object : StoredString {
            override fun read() = values[key]
            override fun write(value: String) {
                values[key] = value
                writes += key
            }
        }
        fun store() = AppModel.camerasStore(at("document"), at("legacy"))
    }

    private fun fixture(name: String) = checkNotNull(javaClass.getResource("/saved-cameras/$name.json")).readText()

    private fun upgraded(legacy: String = fixture("legacy")): Pair<Prefs, SavedCamerasStore> {
        val prefs = Prefs("legacy" to legacy)
        return prefs to prefs.store().also { it.load() }
    }

    /** The decoder every earlier build runs (`SharedPreferencesSavedCameraStore.decode`): records without an id are skipped. */
    private fun oldRecords(raw: String): List<JSONObject> {
        val array = JSONArray(raw)
        return (0 until array.length()).map { array.getJSONObject(it) }.filter { it.optString("id").isNotEmpty() }
    }

    private val a = "cb1b91d0-1430-34e7-8916-f24d9835a642"
    private val b = "471daad8-c248-32e1-bc26-8c0a4eb45139"
    private val c = "d7e2e146-21bd-3ac0-b983-b0819f1ea70f"
    private val d = "01d6489c-ec77-3b9e-8bd3-7ac083d22774"
    private val e = "c4f51397-e730-37a0-8d6f-7068cd24dc31"

    @Test
    fun upgradeImportsEveryCameraAndLeavesLegacyAlone() {
        val (prefs, store) = upgraded()
        assertEquals(fixture("legacy"), prefs.values["legacy"])
        assertEquals(listOf("document"), prefs.writes, "a read writes only the document; Wi-Fi passwords stay in the Keystore")
        assertEquals(listOf(a, b, c, e), store.cameras.map { it.id })
        assertTrue(store.cameras.all { it.integration == DjiCameraSessionAdapter.INTEGRATION && it.device == null })
        assertTrue(store.cameras.all { it.routes.all { r -> r.bluetooth } })

        val first = store.cameras[0]
        assertEquals("A cam", first.name)
        assertEquals("OsmoPocket4P-1A2B", first.advertisedName)
        assertEquals("Osmo Pocket 4 Pro", first.model)
        assertEquals(listOf("ap"), first.routes.map { it.key })
        assertEquals("OsmoPocket4P-1A2B", first.routes[0].network)
        assertEquals(first.routes[0].id, first.preferredRoute)
        assertEquals(1_759_307_200_250L, first.lastConnected)

        // Both setups that move the camera, the Wi-Fi one last used.
        val second = store.cameras[1]
        assertNull(second.name)
        assertEquals(listOf(RouteKind.CAMERA_ACCESS_POINT, RouteKind.INFRASTRUCTURE_NETWORK, RouteKind.PHONE_HOTSPOT), second.routes.map { it.kind })
        assertEquals(listOf("OsmoPocket3-4D5E", "Studio", "Rig phone"), second.routes.map { it.network })
        assertEquals(second.routes[1].id, second.preferredRoute)

        val third = store.cameras[2]
        assertEquals(listOf("ap"), third.routes.map { it.key })
        assertNull(third.routes[0].network)
        assertNull(third.preferredRoute)
        assertEquals(1_757_307_200_500L, third.lastConnected)

        // A hotspot connect stamped station role, then the hotspot setup was forgotten.
        val fifth = store.cameras[3]
        assertNull(fifth.preferredRoute)
        assertEquals(mapOf("lastSetup" to "phoneHotspot"), fifth.extras)
    }

    @Test
    fun migrationIsIdempotent() {
        val (prefs, first) = upgraded()
        val document = prefs.values["document"]
        repeat(2) {
            val again = prefs.store().also { it.load() }
            assertEquals(first.cameras, again.cameras)
        }
        assertEquals(document, prefs.values["document"])
        assertEquals(fixture("legacy"), prefs.values["legacy"])
        assertEquals(listOf("document"), prefs.writes)
    }

    /** Rename, forget, a moving setup stamped before it connects, a camera Wi-Fi connect and a new pair, read back by the old decoder. */
    @Test
    fun mirrorRoundTripDecodesWithTheOldDecoder() {
        val (prefs, store) = upgraded(fixture("legacy-bad-record"))
        var cameras = store.cameras.map { if (it.id == a) it.copy(name = "Renamed") else it }.filter { it.id != c }
        // B is about to move to its hotspot: the integration remembers it before the attempt.
        cameras = cameras.map { if (it.id == b) DjiIntegration.stamping(it, RouteKind.PHONE_HOTSPOT) else it }
        // E connected over camera Wi-Fi: the station stamp goes, the joined network is its own.
        cameras = cameras.map {
            if (it.id == e) it.copy(preferredRoute = it.routes[0].id, extras = it.extras - "lastSetup", lastConnected = 1_760_000_000_000L) else it
        }
        // D paired; its joined network is B's camera Wi-Fi, which is never saved with it (D9).
        val added = SavedCamera(
            id = d, integration = DjiCameraSessionAdapter.INTEGRATION, advertisedName = "OsmoPocket4P-AABB",
            model = "Osmo Pocket 4 Pro", lastConnected = 1_760_000_001_000L,
        )
        assertTrue(DjiIntegration.ownedElsewhere("OsmoPocket3-4D5E", added, cameras))
        store.save(listOf(added) + cameras)

        val legacy = checkNotNull(prefs.values["legacy"])
        val old = oldRecords(legacy).associateBy { it.getString("id") }
        assertEquals(setOf(a, b, d, e), old.keys)
        assertEquals("Renamed", old.getValue(a).getString("customName"))
        assertEquals("cameraWiFi", old.getValue(a).getString("lastSetup"))
        assertEquals("phoneHotspot", old.getValue(b).getString("lastSetup"), "stamped before it moves the camera")
        assertEquals("Studio", old.getValue(b).getString("wifiSSID"))
        assertEquals("cameraWiFi", old.getValue(e).getString("lastSetup"))
        assertEquals(1_760_000_000_000L, old.getValue(e).getLong("lastConnectedAt"))
        assertEquals("OsmoPocket4P-AABB", old.getValue(d).getString("advertisedName"))
        assertFalse(old.getValue(d).has("customName"))
        val broken = JSONArray(legacy).let { array -> (0 until array.length()).map { array.getJSONObject(it) } }
            .single { !it.has("id") }
        assertTrue(broken.getJSONObject("futureField").getBoolean("kept"), "an unreadable record and its unknown fields survive")

        // The mirror is the new merge base: a reload keeps the document as saved.
        val again = prefs.store().also { it.load() }
        assertEquals(store.cameras, again.cameras)
        assertEquals(legacy, prefs.values["legacy"])
    }

    @Test
    fun downgradeEditsMergeBackOnUpgrade() {
        val (prefs, store) = upgraded()
        val serial = CameraDeviceID.durable("SN-1", DjiCameraSessionAdapter.INTEGRATION)
        val ap = store.cameras[0].routes[0].copy(title = "Field")
        store.save(listOf(store.cameras[0].copy(device = serial, routes = listOf(ap))) + store.cameras.drop(1))
        assertEquals(fixture("legacy"), prefs.values["legacy"], "document-only edits leave the legacy records alone")

        // The older build renames B, forgets C, pairs D, adds a hotspot setup on A and connects over it.
        prefs.values["legacy"] = fixture("legacy-downgrade-edits")
        val upgraded = prefs.store().also { it.load() }.cameras.associateBy { it.id }
        assertEquals(setOf(a, b, d, e), upgraded.keys)
        assertEquals("B cam", upgraded.getValue(b).name)
        val first = upgraded.getValue(a)
        assertEquals(serial, first.device)
        assertEquals(ap, first.routes[0], "route id and title survive")
        assertEquals(listOf("ap", "hotspot"), first.routes.map { it.key })
        assertEquals("Rig phone", first.routes[1].network)
        assertEquals(first.routes[1].id, first.preferredRoute)
        assertEquals(1_761_307_200_000L, first.lastConnected)
        val fourth = upgraded.getValue(d)
        assertEquals("OsmoPocket4P-AABB", fourth.routes.single().network)
        assertEquals(fourth.routes[0].id, fourth.preferredRoute)
        assertEquals("phoneHotspot", upgraded.getValue(e).extras["lastSetup"])
    }

    @Test
    fun aBadRecordIsKeptAndNeverOverwritten() {
        val (prefs, store) = upgraded(fixture("legacy-bad-record"))
        assertEquals(listOf(a, b, c, e), store.cameras.map { it.id }, "one unreadable record no longer empties the list (D6)")
        store.save(store.cameras.map { if (it.id == c) it.copy(name = "C cam") else it })
        val raw = JSONArray(checkNotNull(prefs.values["legacy"]))
        val records = (0 until raw.length()).map { raw.getJSONObject(it) }
        assertEquals(5, records.size)
        assertEquals("Broken", records.single { !it.has("id") }.getString("advertisedName"))
        assertEquals("C cam", records.single { it.optString("id") == c }.getString("customName"))
    }

    @Test
    fun aFutureDocumentIsNeverWritten() {
        val future = """{"version":2,"cameras":[],"legacy":{}}"""
        val prefs = Prefs("legacy" to fixture("legacy"), "document" to future)
        val store = prefs.store().also { it.load() }
        assertFalse(store.writesDocument)
        assertEquals(listOf(a, b, c, e), store.cameras.map { it.id }, "this build runs from legacy")
        store.save(store.cameras.map { if (it.id == a) it.copy(name = "Later") else it })
        assertEquals(future, prefs.values["document"])
        assertEquals("Later", oldRecords(checkNotNull(prefs.values["legacy"])).single { it.getString("id") == a }.getString("customName"))
        assertEquals(listOf("legacy"), prefs.writes)
    }
}
