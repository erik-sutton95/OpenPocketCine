package com.opencapture.openpocketcine.media

import android.content.SharedPreferences
import java.util.concurrent.CopyOnWriteArraySet

/** SIMULATED exact preference bytes for the actual host adapter; no Android process storage. */
internal class PocketMediaTestPreferences : SharedPreferences {
    private val values = linkedMapOf<String, Any?>()
    override fun getAll(): MutableMap<String, *> = values.toMutableMap()
    override fun getString(key: String?, defValue: String?): String? = values[key] as? String ?: defValue
    override fun getStringSet(key: String?, defValues: MutableSet<String>?): MutableSet<String>? =
        (values[key] as? Set<*>)?.filterIsInstance<String>()?.toMutableSet() ?: defValues
    override fun getInt(key: String?, defValue: Int): Int = values[key] as? Int ?: defValue
    override fun getLong(key: String?, defValue: Long): Long = values[key] as? Long ?: defValue
    override fun getFloat(key: String?, defValue: Float): Float = values[key] as? Float ?: defValue
    override fun getBoolean(key: String?, defValue: Boolean): Boolean = values[key] as? Boolean ?: defValue
    override fun contains(key: String?): Boolean = values.containsKey(key)
    override fun registerOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener?) {}
    override fun unregisterOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener?) {}
    override fun edit(): SharedPreferences.Editor = object : SharedPreferences.Editor {
        private val pending = linkedMapOf<String, Any?>()
        private var clear = false
        override fun putString(key: String?, value: String?): SharedPreferences.Editor = apply { pending[requireNotNull(key)] = value }
        override fun putStringSet(key: String?, values: MutableSet<String>?): SharedPreferences.Editor = apply { pending[requireNotNull(key)] = values?.toSet() }
        override fun putInt(key: String?, value: Int): SharedPreferences.Editor = apply { pending[requireNotNull(key)] = value }
        override fun putLong(key: String?, value: Long): SharedPreferences.Editor = apply { pending[requireNotNull(key)] = value }
        override fun putFloat(key: String?, value: Float): SharedPreferences.Editor = apply { pending[requireNotNull(key)] = value }
        override fun putBoolean(key: String?, value: Boolean): SharedPreferences.Editor = apply { pending[requireNotNull(key)] = value }
        override fun remove(key: String?): SharedPreferences.Editor = apply { pending[requireNotNull(key)] = null }
        override fun clear(): SharedPreferences.Editor = apply { clear = true }
        override fun commit(): Boolean {
            if (clear) values.clear()
            pending.forEach { (key, value) -> if (value == null) values.remove(key) else values[key] = value }
            return true
        }
        override fun apply() { commit() }
    }
}
