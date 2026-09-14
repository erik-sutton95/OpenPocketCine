package com.opencapture.openpocketcine.diagnostics

import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.atomic.AtomicInteger

/**
 * Bounded in-memory journal. Callers never wait on disk. A dedicated writer
 * persists batches; a full queue drops rather than blocking the feed path.
 */
internal class DiagnosticJournal(
    private val cap: Int,
    private val queueCap: Int = 256,
) {
    private val ringLock = Any()
    private val ring = ArrayDeque<String>(cap)
    private val pending = ArrayBlockingQueue<String>(queueCap)
    private val dropped = AtomicInteger(0)
    @Volatile private var persist: ((List<String>) -> Unit)? = null
    @Volatile private var writer: Thread? = null

    fun append(line: String) {
        synchronized(ringLock) {
            if (ring.size >= cap) ring.removeFirst()
            ring.addLast(line)
        }
        if (persist == null) return
        if (!pending.offer(line)) dropped.incrementAndGet()
    }

    fun snapshot(): List<String> = synchronized(ringLock) { ring.toList() }

    fun droppedCount(): Int = dropped.get()

    fun pendingCount(): Int = pending.size

    fun startWriter(persistLines: (List<String>) -> Unit) {
        persist = persistLines
        if (writer != null) return
        writer =
            Thread(
                {
                    val batch = ArrayList<String>(32)
                    while (!Thread.currentThread().isInterrupted) {
                        val first =
                            try {
                                pending.take()
                            } catch (_: InterruptedException) {
                                break
                            }
                        batch.clear()
                        batch.add(first)
                        pending.drainTo(batch, 31)
                        runCatching { persistLines(ArrayList(batch)) }
                    }
                },
                "opc.diag.journal",
            ).also {
                it.isDaemon = true
                it.start()
            }
    }

    fun shutdownWriter() {
        persist = null
        writer?.interrupt()
        writer = null
        pending.clear()
    }
}
