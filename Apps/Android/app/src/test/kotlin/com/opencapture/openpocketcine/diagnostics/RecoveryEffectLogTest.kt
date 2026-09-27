package com.opencapture.openpocketcine.diagnostics

import kotlin.test.Test
import kotlin.test.assertEquals

class RecoveryEffectLogTest {
    @Test
    fun requestedBlockedSentAndFreshPictureUseSharedNames() {
        val cases =
            listOf(
                Triple(RecoveryAction.DECODER, RecoveryEffect.REQUESTED, RecoveryReason.REFERENCE_LOSS) to
                    "recovery: action=decoder effect=requested reason=referenceLoss",
                Triple(RecoveryAction.DECODER, RecoveryEffect.REQUESTED, RecoveryReason.OUTPUT_SILENCE) to
                    "recovery: action=decoder effect=requested reason=outputSilence",
                Triple(RecoveryAction.ENABLE, RecoveryEffect.BLOCKED, RecoveryReason.NOT_READY) to
                    "recovery: action=enable effect=blocked reason=notReady",
                Triple(RecoveryAction.ENABLE, RecoveryEffect.SENT, RecoveryReason.WATCHDOG) to
                    "recovery: action=enable effect=sent reason=watchdog",
                Triple(RecoveryAction.DECODER, RecoveryEffect.FRESH_PICTURE, RecoveryReason.OUTPUT_RESUMED) to
                    "recovery: action=decoder effect=freshPicture reason=outputResumed",
            )
        for ((input, expected) in cases) {
            val (action, effect, reason) = input
            assertEquals(expected, RecoveryEffectLog.line(action, effect, reason))
        }
    }
}
