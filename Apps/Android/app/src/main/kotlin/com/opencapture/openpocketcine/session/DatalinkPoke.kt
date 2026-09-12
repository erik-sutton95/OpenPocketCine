package com.opencapture.openpocketcine.session

/** A TCP poke is optional, but its cancellation and resource ownership are not. */
internal fun <Resource : AutoCloseable> openDatalinkPoke(
    resource: Resource,
    ensureActive: () -> Unit,
    initialize: (Resource) -> Unit,
    settle: () -> Unit,
    publish: (Resource) -> Unit,
    onFailure: (Exception) -> Unit,
    connect: (Resource) -> Unit = {},
): Boolean {
    var transferred = false
    try {
        ensureActive()
        connect(resource)
        ensureActive() // A cancelled TCP connect must not emit the pairing PIN.
        initialize(resource)
        ensureActive()
        settle()
        ensureActive()
        publish(resource)
        transferred = true
        return true
    } catch (interrupted: InterruptedException) {
        // Thread.sleep clears the interrupt bit. Do not swallow it and start UDP.
        throw interrupted
    } catch (error: Exception) {
        onFailure(error)
        return false
    } finally {
        if (!transferred) runCatching { resource.close() }
    }
}
