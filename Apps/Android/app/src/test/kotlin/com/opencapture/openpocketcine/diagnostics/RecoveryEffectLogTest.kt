package com.opencapture.openpocketcine.diagnostics

import kotlin.test.Test
import kotlin.test.assertEquals

class RecoveryEffectLogTest {
    @Test
    fun requestedBlockedSentAndFreshPictureUseSharedNames() {
        assertEquals(
            "recovery: action=decoder effect=requested reason=referenceLoss",
            RecoveryEffectLog.line(
                RecoveryAction.DECODER,
                RecoveryEffect.REQUESTED,
                RecoveryReason.REFERENCE_LOSS,
            ),
        )
        assertEquals(
            "recovery: action=decoder effect=requested reason=outputSilence",
            RecoveryEffectLog.line(
                RecoveryAction.DECODER,
                RecoveryEffect.REQUESTED,
                RecoveryReason.OUTPUT_SILENCE,
            ),
        )
        assertEquals(
            "recovery: action=enable effect=blocked reason=notReady",
            RecoveryEffectLog.line(
                RecoveryAction.ENABLE,
                RecoveryEffect.BLOCKED,
                RecoveryReason.NOT_READY,
            ),
        )
        assertEquals(
            "recovery: action=enable effect=sent reason=watchdog",
            RecoveryEffectLog.line(
                RecoveryAction.ENABLE,
                RecoveryEffect.SENT,
                RecoveryReason.WATCHDOG,
            ),
        )
        assertEquals(
            "recovery: action=decoder effect=freshPicture reason=outputResumed",
            RecoveryEffectLog.line(
                RecoveryAction.DECODER,
                RecoveryEffect.FRESH_PICTURE,
                RecoveryReason.OUTPUT_RESUMED,
            ),
        )
    }
}
