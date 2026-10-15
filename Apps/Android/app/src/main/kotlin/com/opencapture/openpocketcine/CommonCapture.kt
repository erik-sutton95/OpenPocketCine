package com.opencapture.openpocketcine

import com.opencapture.opencine.core.SettingValue
import com.opencapture.opencine.vocabulary.FocusTrackMode

/** AF-C must retain the native strategy reset when tracking is unknown or non-default. */
internal fun commonFocusValue(label: String, track: FocusTrackMode?): SettingValue? =
    com.opencapture.opencine.cameracontrols.captureFocusValue(label, track)
