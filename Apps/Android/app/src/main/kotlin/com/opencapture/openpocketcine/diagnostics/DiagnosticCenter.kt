package com.opencapture.openpocketcine.diagnostics

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.content.FileProvider
import com.opencapture.openpocketcine.BuildConfig
import com.opencapture.openpocketcine.media.MediaShare
import com.opencapture.openpocketcine.session.LocalVPNFilter
import com.opencapture.openpocketcine.session.PocketCameraSession
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.atomic.AtomicBoolean

/**
 * On-device journal, exceptions, and a shareable report. Optional uploads belong
 * to ReliabilityReporting. Person name, location, device name, and Wi-Fi passwords are stripped.
 */
object DiagnosticCenter {
    private const val TAG = "opc.diagnostics"
    private const val JOURNAL_CAP = 2500
    private const val EXCEPTION_CAP = 200
    private const val SHARE_MAX_BYTES = 2_097_152L
    private val iso = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
        timeZone = TimeZone.getTimeZone("UTC")
    }

    @Volatile private var appContext: Context? = null
    @Volatile var onCopiedForFeedback: (() -> Unit)? = null
    internal val journal = DiagnosticJournal(JOURNAL_CAP)
    internal val exceptionJournal = DiagnosticJournal(EXCEPTION_CAP)
    private val journalWritten = java.util.concurrent.atomic.AtomicInteger(0)
    private val exceptionWritten = java.util.concurrent.atomic.AtomicInteger(0)
    private val sharing = AtomicBoolean(false)

    fun install(context: Context) {
        appContext = context.applicationContext
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            recordFault("uncaught", error.stackTraceToString())
            previous?.uncaughtException(thread, error)
        }
        journal.startWriter { batch -> persistBatch(journalFile(), batch, JOURNAL_CAP, journalWritten, journal) }
        exceptionJournal.startWriter { batch ->
            persistBatch(exceptionFile(), batch, EXCEPTION_CAP, exceptionWritten, exceptionJournal)
        }
        filesDir()?.let { FeedIncidentRuntime.install(it) }
        ReliabilityReporting.install(context.applicationContext)
        ManualProblemReport.install(context.applicationContext)
        log("notice", "diagnostics", "boot", "diagnostics installed")
    }

    fun boundedDiagnosticText(
        session: PocketCameraSession,
        maxBytes: Int = ManualProblemReport.ATTACHMENT_MAX_BYTES,
        maxChars: Int = ManualProblemReport.ATTACHMENT_MAX_CHARS,
    ): String {
        val env = environment(session)
        val body =
            BoundedDiagnosticFormatter.format(
                environment =
                    BoundedDiagnosticFormatter.Environment(
                        appVersion = env.appVersion,
                        appBuild = env.appBuild,
                        osName = env.osName,
                        osVersion = env.osVersion,
                        deviceModel = env.deviceModel,
                        cameraFamily = env.cameraFamily,
                        cameraModel = env.cameraModel,
                        phase = env.phase,
                        vpnActive = env.vpnActive,
                    ),
                journal = journalLines(),
                exceptions = exceptionLines(),
                extras = FeedIncidentRuntime.reportExtras(),
                cap = minOf(maxChars, BoundedDiagnosticFormatter.CHARACTER_CAP),
            )
        return ManualProblemReportEnvelope.utf8Prefix(body, maxBytes)
    }

    fun log(level: String, category: String, code: String, message: String) {
        val line = PrivacyRedactor.redact("$level $category $code $message")
        when (level) {
            "error", "fault" -> Log.e(TAG, line)
            "warning" -> Log.w(TAG, line)
            else -> Log.i(TAG, line)
        }
        if (level != "debug") journal.append(line)
        if (level == "error" || level == "fault") exceptionJournal.append(line)
    }

    fun recordFault(code: String, stack: String) {
        log("fault", "diagnostics", code, PrivacyRedactor.redact(stack.take(4000)))
    }

    fun writeReport(context: Context, session: PocketCameraSession): File? {
        val env = environment(session)
        val journal = journalLines()
        val exceptions = exceptionLines()
        return writeShareFiles(context, env, journal, exceptions, FeedIncidentRuntime.exportExtras())
            .firstOrNull { it.name == "report.txt" }
    }

    fun shareReport(context: Context, session: PocketCameraSession, emailSupport: Boolean = false, copyForFeedback: Boolean = true) {
        if (!sharing.compareAndSet(false, true)) {
            android.widget.Toast.makeText(context, "Preparing the report…", android.widget.Toast.LENGTH_SHORT).show()
            return
        }
        if (!emailSupport && copyForFeedback) copyCompact(context, session)
        val app = context.applicationContext
        val env = environment(session)
        val journal = journalLines()
        val exceptions = exceptionLines()
        Thread(
            {
                try {
                    val extras = FeedIncidentRuntime.exportExtras()
                    val files = writeShareFiles(app, env, journal, exceptions, extras)
                    Handler(Looper.getMainLooper()).post { launchShare(app, files, emailSupport) }
                } catch (_: Exception) {
                    Handler(Looper.getMainLooper()).post {
                        android.widget.Toast.makeText(app,
                            "Couldn't prepare the report. Please try again or email support@openpocketcine.app.",
                            android.widget.Toast.LENGTH_LONG).show()
                    }
                } finally {
                    sharing.set(false)
                }
            },
            "opc.diag.share",
        ).apply { isDaemon = true; start() }
    }

    private fun writeShareFiles(
        context: Context,
        env: Env,
        journal: List<String>,
        exceptions: List<String>,
        extras: List<Pair<String, String>>,
    ): List<File> {
        val dir = File(context.cacheDir, "diagnostics").apply { mkdirs() }
        dir.listFiles()?.filter { it.name.startsWith("incident-") || it.name == "incidents.txt" }?.forEach { it.delete() }
        val report = File(dir, "report.txt")
        var body = fullReport(env, journal, exceptions, extras)
        if (body.length > SHARE_MAX_BYTES) {
            body = fullReport(env, emptyList(), exceptions, extras)
        }
        if (body.length > SHARE_MAX_BYTES) {
            body = body.take(SHARE_MAX_BYTES.toInt())
        }
        report.writeText(body)
        val files = mutableListOf(report)
        var bytes = report.length()
        for ((name, body) in extras) {
            if (bytes >= SHARE_MAX_BYTES) break
            val safe = name.filter { it.isLetterOrDigit() || it == '-' || it == '.' }
            if (safe.isEmpty() || safe == "report.txt") continue
            val remaining = SHARE_MAX_BYTES - bytes
            if (body.length.toLong() > remaining) break
            val file = File(dir, safe)
            file.writeText(body)
            bytes += file.length()
            files += file
        }
        log("notice", "diagnostics", "report", "wrote diagnostic report attachments=${files.size}")
        return files
    }

    private fun launchShare(context: Context, files: List<File>, emailSupport: Boolean = false) {
        if (files.isEmpty()) {
            android.widget.Toast.makeText(context, "Couldn't prepare a diagnostic report. Please try again.",
                android.widget.Toast.LENGTH_LONG).show()
            return
        }
        val uris = ArrayList<Uri>()
        for (file in files) {
            val uri =
                runCatching {
                    FileProvider.getUriForFile(context, MediaShare.authority(context), file)
                }.getOrNull() ?: continue
            uris.add(uri)
        }
        if (uris.isEmpty()) {
            android.widget.Toast.makeText(context, "Couldn't attach the diagnostic report. Please try again.",
                android.widget.Toast.LENGTH_LONG).show()
            return
        }
        val clip = ClipData.newRawUri("OpenPocketCine diagnostics", uris[0])
        for (i in 1 until uris.size) clip.addItem(ClipData.Item(uris[i]))
        val intent =
            if (uris.size == 1) {
                Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    clipData = clip
                    putExtra(Intent.EXTRA_STREAM, uris[0])
                    putExtra(Intent.EXTRA_TEXT, lastCompact)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
            } else {
                Intent(Intent.ACTION_SEND_MULTIPLE).apply {
                    type = "text/plain"
                    clipData = clip
                    putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
                    putExtra(Intent.EXTRA_TEXT, lastCompact)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
            }
        if (emailSupport) {
            intent.selector = Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:"))
            intent.putExtra(Intent.EXTRA_EMAIL, arrayOf("support@openpocketcine.app"))
            intent.putExtra(Intent.EXTRA_SUBJECT, "OpenPocketCine — report a problem")
            intent.putExtra(Intent.EXTRA_TEXT,
                "What happened?\n\n\nTechnical details are attached to help us investigate. Please do not include private footage or passwords.")
        }
        val chooser = Intent.createChooser(intent, if (emailSupport) "Email support" else null)
        if (context !is android.app.Activity) chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            context.startActivity(chooser)
        } catch (_: android.content.ActivityNotFoundException) {
            android.widget.Toast.makeText(context,
                "Email support@openpocketcine.app. No compatible app is available.",
                android.widget.Toast.LENGTH_LONG).show()
        }
    }

    @Volatile var lastCompact: String = ""
        private set

    fun copyCompact(context: Context, session: PocketCameraSession) {
        val text = compactSummary(environment(session), journalLines())
        lastCompact = text
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText("OpenPocketCine diagnostics", text))
        log("notice", "diagnostics", "feedback-paste", "copied compact diagnostics")
        onCopiedForFeedback?.invoke()
    }

    private fun environment(session: PocketCameraSession): Env {
        val family = session.connectedCamera?.model?.family ?: "none"
        val model = session.connectedCamera?.model?.name ?: "none"
        val phase = session.phase.name.lowercase()
        val vpn = appContext?.let { LocalVPNFilter.isActive(it) } ?: false
        return Env(
            appVersion = BuildConfig.VERSION_NAME,
            appBuild = BuildConfig.VERSION_CODE.toString(),
            sourceRevision = BuildConfig.SOURCE_REVISION,
            osName = "Android",
            osVersion = Build.VERSION.RELEASE ?: "?",
            deviceModel = Build.MODEL ?: "unknown",
            cameraFamily = family,
            cameraModel = model,
            phase = phase,
            vpnActive = vpn,
        )
    }

    private fun compactSummary(env: Env, recent: List<String>): String {
        val lines =
            mutableListOf(
                "OpenPocketCine diagnostics (no name, no location)",
                "app ${env.appVersion} (${env.appBuild}) source=${env.sourceRevision} ${env.osName} ${env.osVersion} ${env.deviceModel}",
                "camera ${env.cameraModel} family=${env.cameraFamily} phase=${env.phase} vpn=${if (env.vpnActive) "on" else "off"}",
            )
        val tail = recent.takeLast(12)
        if (tail.isNotEmpty()) {
            lines += "recent:"
            lines += tail
        }
        return PrivacyRedactor.clampCompact(PrivacyRedactor.redact(lines.joinToString("\n")))
    }

    private fun fullReport(
        env: Env,
        journal: List<String>,
        exceptions: List<String>,
        extras: List<Pair<String, String>> = emptyList(),
    ): String {
        val sections = mutableListOf<String>()
        sections +=
            """
            OpenPocketCine diagnostic report
            Privacy: no personal name, email, location, device name, or Wi-Fi password.
            Generated for a tester to paste or share. Not uploaded.

            app: ${env.appVersion} (${env.appBuild})
            source: ${env.sourceRevision}
            os: ${env.osName} ${env.osVersion}
            device: ${env.deviceModel}
            camera: ${env.cameraModel}
            family: ${env.cameraFamily}
            phase: ${env.phase}
            vpn: ${if (env.vpnActive) "on" else "off"}
            """.trimIndent()
        if (exceptions.isNotEmpty()) {
            sections += "Exceptions / faults\n" + exceptions.takeLast(EXCEPTION_CAP).joinToString("\n")
        }
        for ((name, body) in extras) {
            if (body.isNotBlank()) sections += "$name\n$body"
        }
        if (journal.isNotEmpty()) {
            sections +=
                "Journal (last ${minOf(journal.size, JOURNAL_CAP)} lines)\n" +
                    journal.takeLast(JOURNAL_CAP).joinToString("\n")
        }
        return PrivacyRedactor.redact(sections.joinToString("\n\n"))
    }

    private fun filesDir(): File? {
        val ctx = appContext ?: return null
        return File(ctx.filesDir, "diagnostics").apply { mkdirs() }
    }

    private fun journalFile(): File? = filesDir()?.let { File(it, "control-live.log") }

    private fun exceptionFile(): File? = filesDir()?.let { File(it, "exceptions.log") }

    private fun journalLines(): List<String> = journal.snapshot()

    private fun exceptionLines(): List<String> = exceptionJournal.snapshot()

    private fun persistBatch(
        file: File?,
        batch: List<String>,
        cap: Int,
        written: java.util.concurrent.atomic.AtomicInteger,
        source: DiagnosticJournal,
    ) {
        if (file == null || batch.isEmpty()) return
        runCatching {
            val stamped = batch.joinToString("") { "${iso.format(Date())} $it\n" }
            file.appendText(stamped)
            val count = written.addAndGet(batch.size)
            if (count >= cap * 2) {
                val keep = source.snapshot()
                file.writeText(keep.joinToString("\n") + "\n")
                written.set(keep.size)
            }
        }
    }

    private data class Env(
        val appVersion: String,
        val appBuild: String,
        val sourceRevision: String,
        val osName: String,
        val osVersion: String,
        val deviceModel: String,
        val cameraFamily: String,
        val cameraModel: String,
        val phase: String,
        val vpnActive: Boolean,
    )
}
