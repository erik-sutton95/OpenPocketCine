package com.opencapture.openpocketcine.multiview

import com.opencapture.opencine.dji.MultiviewNetworkStore
import android.content.Context
import androidx.core.content.edit
import com.opencapture.opencine.appkit.MultiviewStageJournal
import com.opencapture.opencine.dji.KeystoreSeal
import com.opencapture.opencine.multicam.ResourceBudget

/** This app's existing four-camera qualification. Stage validation and admission share it. */
internal object MultiviewQualificationPolicy {
    val budget = ResourceBudget(qualifiedEntries = 4)
    val tileCount: Int = requireNotNull(budget.qualifiedEntries) { "Multiview requires a finite app qualification budget" }
}

/** Device-only stage metadata and camera-Wi-Fi cleanup ledger. Credentials stay in [MultiviewNetworkStore]. The stage types and codec are OpenCine's [MultiviewStageJournal]. */
object MultiviewStageStore {
    fun load(context: Context): MultiviewStageJournal.Stage? =
        prefs(context).getString(KEY, null)?.let(::decode)

    fun save(context: Context, stage: MultiviewStageJournal.Stage?): Boolean {
        if (stage == null) {
            prefs(context).edit { remove(KEY) }
            return true
        }
        if (stage.validated(MultiviewQualificationPolicy.tileCount) == null) return false
        prefs(context).edit(commit = true) { putString(KEY, MultiviewStageJournal.encode(stage)) }
        return true
    }

    fun encode(stage: MultiviewStageJournal.Stage): String = MultiviewStageJournal.encode(stage)

    /** The stored stage when it reads and is valid for this app's tile count. */
    fun decode(raw: String): MultiviewStageJournal.Stage? =
        MultiviewStageJournal.decode(raw)?.validated(MultiviewQualificationPolicy.tileCount)

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private const val PREFS = "openpocketcine.multiview-stage"
    private const val KEY = "stage"
}

internal fun hex(bytes: ByteArray): String = bytes.joinToString("") { "%02x".format(it.toInt() and 0xFF) }
