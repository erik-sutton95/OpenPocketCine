package com.opencapture.openpocketcine.media

import com.opencapture.opencine.appkit.MonitorMediaLibraryActionToken
import com.opencapture.opencine.appkit.MonitorMediaLibraryModel
import com.opencapture.opencine.media.MediaAssetID
import kotlin.properties.ReadOnlyProperty
import kotlin.properties.ReadWriteProperty
import kotlin.reflect.KProperty
import com.opencapture.opencine.vocabulary.MediaFile

/** Value/action bindings read the actual owner on every invocation; they store no presentation state. */
internal fun <T> libraryRead(read: () -> T): ReadOnlyProperty<Any?, T> = object : ReadOnlyProperty<Any?, T> {
    override fun getValue(thisRef: Any?, property: KProperty<*>): T = read()
}
internal fun <T> libraryValue(read: () -> T, write: (T) -> Unit): ReadWriteProperty<Any?, T> = object : ReadWriteProperty<Any?, T> {
    override fun getValue(thisRef: Any?, property: KProperty<*>): T = read()
    override fun setValue(thisRef: Any?, property: KProperty<*>, value: T) { write(value) }
}

/** A rendered legacy row ID routes only to the actual content-qualified asset captured for that row. */
internal class PocketMediaSelectionBridge(
    private val owner: MonitorMediaLibraryModel<MediaFile>,
    private val token: MonitorMediaLibraryActionToken = owner.actionToken,
    private val renderedIDs: Map<String, MediaAssetID> = owner.state.value.records.associate { it.payload.id to it.asset.id },
) {
    val selectedIDs: Set<String> get() = owner.state.value.records
        .filter { it.asset.id in owner.state.value.selectedIDs }.map { it.payload.id }.toSet()
    fun apply(selecting: Boolean, ids: Set<String>) {
        if (!owner.isCurrent(token)) return
        val requested = ids.map { renderedIDs[it] ?: return }
        if (requested.any { owner.record(it) == null }) return
        owner.select(requested.toSet(), selecting)
    }
}

/** Admitted host metadata changes only the actual record facts, never the source catalog/page count. */
internal fun applyPocketMediaColor(owner: MonitorMediaLibraryModel<MediaFile>,
    codec: PocketMediaLibraryCodec, file: MediaFile, mode: Int,
    token: MonitorMediaLibraryActionToken): Boolean {
    if (mode < 0 || !owner.isCurrent(token)) return false
    val current = owner.record(com.opencapture.opencine.dji.DjiAndroidMediaAssets.asset(file).id) ?: return false
    owner.updateLocalFacts(mapOf(current.asset.id to codec.record(current.payload, mode).facts), token)
    return owner.isCurrent(token)
}
