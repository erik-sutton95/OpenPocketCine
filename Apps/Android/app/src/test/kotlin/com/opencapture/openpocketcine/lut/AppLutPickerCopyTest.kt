package com.opencapture.openpocketcine.lut

import com.opencapture.opencine.cameracontrols.LutPickerCopy
import com.opencapture.opencine.vocabulary.LutCatalog
import kotlin.test.Test
import kotlin.test.assertEquals

/** Pocket's LUT picker words and Auto, as on main. */
class AppLutPickerCopyTest {
    @Test fun officialCubesSitOnTheDjiTab() {
        assertEquals(
            LutPickerCopy(
                cameraTab = "DJI",
                autoId = LutCatalog.OFFICIAL_AUTO,
                customHint = "Imported looks land here. Auto stays on Built-in or DJI.",
                noLookCaption = "No matching look for this color / camera",
                officialCubeCaption = "Official DJI Rec.709 cube",
                cameraLooksCaption = "Official DJI looks for this color / camera",
            ),
            AppLutPickerCopy,
        )
        assertEquals("djiAuto", AppLutPickerCopy.autoId)
    }
}
