package com.opencapture.openpocketcine.media

import java.io.File

/** App-owned files/message facts. A prepared result does not launch an OS intent. */
internal sealed interface MediaDeliveryResult {
    data class Message(val text: String) : MediaDeliveryResult
    data class ShareReady(val files: List<File>) : MediaDeliveryResult
}

/** Called only by the current admitted completion on the presentation dispatcher. */
internal fun admittedDeliveryToast(
    outcome: MediaDeliveryResult,
    share: (List<File>) -> Boolean,
): String = when (outcome) {
    is MediaDeliveryResult.Message -> outcome.text
    is MediaDeliveryResult.ShareReady -> {
        if (!share(outcome.files)) {
            if (outcome.files.size == 1) "Couldn't share this clip." else "Couldn't share these clips."
        } else {
            "Ready to share ${outcome.files.size} clip${if (outcome.files.size == 1) "" else "s"}"
        }
    }
}
