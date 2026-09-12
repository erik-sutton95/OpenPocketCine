package com.opencapture.openpocketcine.session

/** Identity fence for callbacks, queued starts and cancellation across reconnects. */
internal class CallbackOperationOwner<Resource : Any> {
    internal class Token<Resource : Any> {
        var resource: Resource? = null
            internal set
    }

    private var current: Token<Resource>? = null

    @Synchronized
    fun begin(): Token<Resource> = Token<Resource>().also { current = it }

    @Synchronized
    fun current(): Token<Resource>? = current

    @Synchronized
    fun attach(token: Token<Resource>, resource: Resource) {
        if (current === token) token.resource = resource
    }

    @Synchronized
    fun runIfCurrent(token: Token<Resource>, resource: Resource? = null, action: () -> Unit): Boolean {
        if (current !== token || (resource != null && token.resource !== resource)) return false
        action()
        return true
    }

    @Synchronized
    fun finish(token: Token<Resource>) {
        if (current === token) current = null
    }
}

/** Even a start rejected before installation must complete its local caller. */
internal fun <Resource : Any> runOwnedConnectionStart(
    owner: CallbackOperationOwner<Resource>,
    token: CallbackOperationOwner.Token<Resource>,
    continuation: kotlinx.coroutines.CancellableContinuation<Unit>,
    start: () -> Unit,
) {
    if (!owner.runIfCurrent(token, action = start) && continuation.isActive) {
        continuation.resumeWith(Result.failure(IllegalStateException("Bluetooth connection replaced")))
    }
}
