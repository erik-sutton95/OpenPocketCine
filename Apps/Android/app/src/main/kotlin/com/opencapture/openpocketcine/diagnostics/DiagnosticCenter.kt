package com.opencapture.openpocketcine.diagnostics

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.content.FileProvider
import com.opencapture.openpocketcine.BuildConfig
import com.opencapture.openpocketcine.media.MediaShare
import com.opencapture.openpocketcine.session.PocketCameraSession
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * On-device journal, exceptions, and a shareable report. Nothing is uploaded.
 * Person name, location, device name, and Wi-Fi passwords are stripped.
 */
object DiagnosticCenter {
    private const val TAG = "opc.diagnostics"
    private const val JOURNAL_CAP = 2500
    private const val EXCEPTION_CAP = 200
    private val iso = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
        timeZone = TimeZone.getTimeZone("UTC")
    }

    @Volatile private var appContext: Context? = null
    @Volatile var onCopiedForFeedback: (() -> Unit)? = null

    fun install(context: Context) {
        appContext = context.applicationContext
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            recordFault("uncaught", error.stackTraceToString())
            previous?.uncaughtException(thread, error)
        }
        log("notice", "diagnostics", "boot", "diagnostics installed")
    }

    fun log(level: String, category: String, code: String, message: String) {
        val line = PrivacyRedactor.redact("$level $category $code $message")
        when (level) {
            "error", "fault" -> Log.e(TAG, line)
            "warning" -> Log.w(TAG, line)
            else -> Log.i(TAG, line)
        }
        if (level != "debug") appendJournal(line)
        if (level == "error" || level == "fault") appendException(line)
    }

    fun recordFault(code: String, stack: String) {
        log("fault", "diagnostics", code, PrivacyRedactor.redact(stack.take(4000)))
    }

    fun writeReport(context: Context, session: PocketCameraSession): File? {
        val env = environment(session)
        val journal = journalLines()
        val exceptions = exceptionLines()
        val body = fullReport(env, journal, exceptions)
        val dir = File(context.cacheDir, "diagnostics").apply { mkdirs() }
        val file = File(dir, "report.txt")
        file.writeText(body)
        log("notice", "diagnostics", "report", "wrote diagnostic report")
        return file
    }

    fun shareReport(context: Context, session: PocketCameraSession) {
        copyCompact(context, session)
        val file = writeReport(context, session) ?: return
        val uri =
            runCatching {
                FileProvider.getUriForFile(context, MediaShare.authority(context), file)
            }
                .getOrNull() ?: return
        val intent =
            Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_STREAM, uri)
                putExtra(Intent.EXTRA_TEXT, lastCompact)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        val chooser = Intent.createChooser(intent, null)
        if (context !is android.app.Activity) chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(chooser)
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
        return Env(
            appVersion = BuildConfig.VERSION_NAME,
            appBuild = BuildConfig.VERSION_CODE.toString(),
            osName = "Android",
            osVersion = Build.VERSION.RELEASE ?: "?",
            deviceModel = Build.MODEL ?: "unknown",
            cameraFamily = family,
            cameraModel = model,
            phase = phase,
        )
    }

    private fun compactSummary(env: Env, recent: List<String>): String {
        val lines =
            mutableListOf(
                "OpenPocketCine diagnostics (no name, no location)",
                "app ${env.appVersion} (${env.appBuild}) ${env.osName} ${env.osVersion} ${env.deviceModel}",
                "camera ${env.cameraModel} family=${env.cameraFamily} phase=${env.phase}",
            )
        val tail = recent.takeLast(12)
        if (tail.isNotEmpty()) {
            lines += "recent:"
            lines += tail
        }
        return PrivacyRedactor.clampCompact(PrivacyRedactor.redact(lines.joinToString("\n")))
    }

    private fun fullReport(env: Env, journal: List<String>, exceptions: List<String>): String {
        val sections = mutableListOf<String>()
        sections +=
            """
            OpenPocketCine diagnostic report
            Privacy: no personal name, email, location, device name, or Wi-Fi password.
            Generated for a tester to paste or share. Not uploaded.

            app: ${env.appVersion} (${env.appBuild})
            os: ${env.osName} ${env.osVersion}
            device: ${env.deviceModel}
            camera: ${env.cameraModel}
            family: ${env.cameraFamily}
            phase: ${env.phase}
            """.trimIndent()
        if (exceptions.isNotEmpty()) {
            sections += "Exceptions / faults\n" + exceptions.takeLast(EXCEPTION_CAP).joinToString("\n")
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

    private fun appendJournal(line: String) {
        val file = journalFile() ?: return
        file.appendText("${iso.format(Date())} $line\n")
        trimFile(file, JOURNAL_CAP)
    }

    private fun appendException(line: String) {
        val file = exceptionFile() ?: return
        file.appendText("${iso.format(Date())} $line\n")
        trimFile(file, EXCEPTION_CAP)
    }

    private fun journalLines(): List<String> = readLines(journalFile())

    private fun exceptionLines(): List<String> = readLines(exceptionFile())

    private fun readLines(file: File?): List<String> {
        if (file == null || !file.exists()) return emptyList()
        return runCatching { file.readLines() }.getOrDefault(emptyList())
    }

    private fun trimFile(file: File, cap: Int) {
        val lines = readLines(file)
        if (lines.size <= cap) return
        file.writeText(lines.takeLast(cap).joinToString("\n") + "\n")
    }

    private data class Env(
        val appVersion: String,
        val appBuild: String,
        val osName: String,
        val osVersion: String,
        val deviceModel: String,
        val cameraFamily: String,
        val cameraModel: String,
        val phase: String,
    )
}
