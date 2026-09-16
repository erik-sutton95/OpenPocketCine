package com.opencapture.openpocketcine.session

import android.os.DeadObjectException
import android.os.RemoteException

/** Play #348: `writeCharacteristic` throws `DeadObjectException` (sometimes wrapped). */
internal object BleBinderFailure {
    fun isDeadBinder(error: Throwable): Boolean {
        var current: Throwable? = error
        val seen = HashSet<Throwable>()
        while (current != null && seen.add(current)) {
            if (current is DeadObjectException || current is RemoteException) return true
            current = current.cause
        }
        return false
    }
}
