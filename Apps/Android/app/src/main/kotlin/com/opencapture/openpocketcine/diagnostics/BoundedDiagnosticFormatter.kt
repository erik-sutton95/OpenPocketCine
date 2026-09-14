package com.opencapture.openpocketcine.diagnostics

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Shell bounded formatter for the native Send form. Keeps environment, newest
 * journal, typed incident/session extras and compact faults inside the cap.
 * JSON extras are omitted whole when they do not fit.
 */
internal object BoundedDiagnosticFormatter {
    const val CHARACTER_CAP = 32_000
    const val RESERVED_JOURNAL = 8_000
    const val RESERVED_EXCEPTIONS = 3_500
    const val RESERVED_TYPED = 10_000
    const val JOURNAL_CAP = 2_500
    const val EXCEPTION_CAP = 200

    data class Environment(
        val appVersion: String,
        val appBuild: String,
        val osName: String,
        val osVersion: String,
        val deviceModel: String,
        val cameraFamily: String,
        val cameraModel: String,
        val phase: String,
        val vpnActive: Boolean,
    )

    fun format(
        environment: Environment,
        journal: List<String>,
        exceptions: List<String>,
        extras: List<Pair<String, String>> = emptyList(),
        generatedAtMs: Long = System.currentTimeMillis(),
        cap: Int = CHARACTER_CAP,
    ): String {
        val journalLines = journal.map { PrivacyRedactor.redact(it) }
        val collectorCount = exceptions.count { isCollectorException(it) }
        val exceptionLines =
            exceptions.map { PrivacyRedactor.redact(it) }.filter { !isCollectorException(it) }
        val typed = mutableListOf<Pair<String, String>>()
        val metricKit = mutableListOf<Pair<String, String>>()
        val other = mutableListOf<Pair<String, String>>()
        for ((rawName, rawBody) in extras) {
            val name = PrivacyRedactor.redact(rawName)
            val body = PrivacyRedactor.redact(rawBody)
            if (name.isEmpty() || body.isEmpty()) continue
            when {
                isTypedIncidentExtra(name) -> typed += name to body
                name.lowercase(Locale.US).startsWith("metrickit-") -> metricKit += name to body
                else -> other += name to body
            }
        }
        val orderedTyped = orderedTypedExtras(typed)
        metricKit.sortByDescending { it.first }

        val header = manualHeader(environment, orderedTyped.isNotEmpty(), generatedAtMs)
        var remaining = maxOf(0, cap - header.length - 1_024)
        val exceptionBudget =
            if (exceptionLines.isEmpty()) 0 else minOf(RESERVED_EXCEPTIONS, remaining)
        remaining -= exceptionBudget
        val typedBudget = if (orderedTyped.isEmpty()) 0 else minOf(RESERVED_TYPED, remaining)
        remaining -= typedBudget
        val journalBudget = if (journalLines.isEmpty()) 0 else minOf(RESERVED_JOURNAL, remaining)
        remaining -= journalBudget

        val omitted = mutableListOf<String>()
        if (collectorCount > 0) {
            omitted += "omitted $collectorCount collector MetricKit stacks"
        }

        val exceptionSection =
            fitLineSection(
                title = "Exceptions / faults",
                lines = exceptionLines.takeLast(EXCEPTION_CAP),
                budget = exceptionBudget,
            )
        var typedFitted =
            fitExtras(orderedTyped, typedBudget, allowTextTruncate = true, omitted = omitted)
        val journalSection =
            fitLineSection(
                title = "Journal",
                lines = journalLines.takeLast(JOURNAL_CAP),
                budget = journalBudget,
            )

        var leftover =
            remaining +
                unusedBudget(exceptionBudget, exceptionSection) +
                unusedBudget(typedBudget, typedFitted) +
                unusedBudget(journalBudget, journalSection)

        val typedIncluded = typedFitted.map { it.substringBefore('\n') }.toSet()
        val typedRemainder = orderedTyped.filter { it.first !in typedIncluded }
        if (leftover > 0 && typedRemainder.isNotEmpty()) {
            val more = fitExtras(typedRemainder, leftover, allowTextTruncate = true, omitted = omitted)
            leftover -= joinedSectionCount(more)
            typedFitted = typedFitted + more
        }
        val otherFitted: List<String>
        if (leftover > 0) {
            otherFitted = fitExtras(other, leftover, allowTextTruncate = false, omitted = omitted)
            leftover -= joinedSectionCount(otherFitted)
        } else {
            for ((name, _) in other) omitted += "omitted extra $name (did not fit)"
            otherFitted = emptyList()
        }
        val metricFitted: List<String>
        if (leftover > 0) {
            metricFitted = fitExtras(metricKit, leftover, allowTextTruncate = false, omitted = omitted)
        } else {
            if (metricKit.isNotEmpty()) {
                omitted += "omitted ${metricKit.size} MetricKit extras that did not fit"
            }
            metricFitted = emptyList()
        }

        val sections = mutableListOf(header)
        exceptionSection?.let { sections += it }
        sections += typedFitted
        journalSection?.let { sections += it }
        sections += otherFitted
        sections += metricFitted
        val includedNames = typedFitted.map { it.substringBefore('\n') }.toSet()
        omitted.removeAll { note -> includedNames.any { note.contains(it) } }
        if (omitted.isNotEmpty()) {
            val notice = omitted.joinToString("; ")
            sections += "[truncated: ${notice.take(900)}${if (notice.length > 900) "; further omissions" else ""}]"
        }
        return clampSections(sections, cap)
    }

    private fun manualHeader(environment: Environment, hasTypedExtras: Boolean, generatedAtMs: Long): String {
        val iso =
            SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
            }
        val lines =
            mutableListOf(
                "OpenPocketCine diagnostic report",
                "Privacy: no personal name, email, location, device name, or Wi-Fi password.",
                "Generated: ${iso.format(Date(generatedAtMs))}",
                "Prepared for explicit manual submission.",
                "Environment below is a report-time snapshot, not necessarily the failure state.",
                "",
                "app: ${environment.appVersion} (${environment.appBuild})",
                "os: ${environment.osName} ${environment.osVersion}",
                "device: ${environment.deviceModel}",
                "camera: ${environment.cameraModel}",
                "family: ${environment.cameraFamily}",
                "phase: ${environment.phase}",
                "vpn: ${if (environment.vpnActive) "on" else "off"}",
            )
        if (!hasTypedExtras) lines += "incidents: none captured"
        return PrivacyRedactor.redact(lines.joinToString("\n"))
    }

    private fun isCollectorException(line: String): Boolean =
        line.contains("MetricKit diagnostic payload received") ||
            line.contains("diagnostics metrickit")

    internal fun isTypedIncidentExtra(name: String): Boolean {
        val lower = name.lowercase(Locale.US)
        if (lower == "incidents.txt") return true
        if (lower == "session-summary.json") return true
        if (lower.startsWith("incident-") && lower.endsWith(".json")) return true
        if (lower.startsWith("session-") && lower.endsWith(".json")) return true
        return false
    }

    private fun orderedTypedExtras(extras: List<Pair<String, String>>): List<Pair<String, String>> {
        val listing = extras.filter { it.first.lowercase(Locale.US) == "incidents.txt" }
        val summaries =
            extras.filter {
                val lower = it.first.lowercase(Locale.US)
                lower == "session-summary.json" || (lower.startsWith("session-") && lower.endsWith(".json"))
            }
        val incidents =
            extras.filter {
                val lower = it.first.lowercase(Locale.US)
                lower.startsWith("incident-") && lower.endsWith(".json")
            }
        return listing + summaries + incidents
    }

    private fun isJsonExtra(name: String, body: String): Boolean {
        if (name.lowercase(Locale.US).endsWith(".json")) return true
        val first = body.firstOrNull { !it.isWhitespace() } ?: return false
        return first == '{' || first == '['
    }

    private fun unusedBudget(budget: Int, section: String?): Int = maxOf(0, budget - (section?.length ?: 0))

    private fun unusedBudget(budget: Int, sections: List<String>): Int =
        maxOf(0, budget - joinedSectionCount(sections))

    private fun joinedSectionCount(sections: List<String>): Int {
        if (sections.isEmpty()) return 0
        return sections.sumOf { it.length } + 2 * (sections.size - 1)
    }

    private fun fitLineSection(title: String, lines: List<String>, budget: Int): String? {
        if (lines.isEmpty() || budget <= 0) return null
        val kept = mutableListOf<String>()
        for (line in lines.asReversed()) {
            val candidateCount = kept.size + 1
            val heading = "$title (last $candidateCount lines)\n"
            val body = (listOf(line) + kept).joinToString("\n")
            val omitted = lines.size - candidateCount
            val suffix = if (omitted > 0) "\n[truncated: omitted $omitted older lines]" else ""
            if (heading.length + body.length + suffix.length > budget) {
                if (kept.isEmpty()) {
                    val marker = "\n[truncated: newest line shortened; older lines omitted]"
                    return heading + line.take(maxOf(0, budget - heading.length - marker.length)) + marker
                }
                break
            }
            kept.add(0, line)
        }
        if (kept.isEmpty()) return null
        val omitted = lines.size - kept.size
        var text = "$title (last ${kept.size} lines)\n" + kept.joinToString("\n")
        if (omitted > 0) text += "\n[truncated: omitted $omitted older lines]"
        return text
    }

    private fun fitExtras(
        extras: List<Pair<String, String>>,
        budget: Int,
        allowTextTruncate: Boolean,
        omitted: MutableList<String>,
    ): List<String> {
        var remaining = budget
        val fitted = mutableListOf<String>()
        for (extra in extras) {
            val json = isJsonExtra(extra.first, extra.second)
            if (json || !allowTextTruncate) {
                val section = "${extra.first}\n${extra.second}"
                val cost = section.length + if (fitted.isEmpty()) 0 else 2
                if (cost <= remaining) {
                    fitted += section
                    remaining -= cost
                } else {
                    omitted += "omitted extra ${extra.first} (did not fit)"
                }
                continue
            }
            val gap = if (fitted.isEmpty()) 0 else 2
            val heading = extra.first + "\n"
            val marker = "\n[truncated: older incident detail omitted]"
            val room = remaining - gap - heading.length
            val section = when {
                room >= extra.second.length -> heading + extra.second
                room > marker.length -> heading + extra.second.take(room - marker.length) + marker
                else -> null
            }
            if (section != null) {
                fitted += section
                remaining -= section.length + gap
            } else {
                omitted += "omitted extra ${extra.first} (did not fit)"
            }
        }
        return fitted
    }

    private fun clampSections(sections: List<String>, cap: Int): String {
        val original = sections.joinToString("\n\n")
        if (original.length <= cap) return original
        val marker = "[truncated: report capped at $cap characters]"
        val kept = sections.toMutableList()
        while (kept.size > 1) {
            kept.removeAt(kept.lastIndex)
            val result = (kept + marker).joinToString("\n\n")
            if (result.length <= cap) return result
        }
        return (kept.firstOrNull().orEmpty().take(maxOf(0, cap - marker.length - 2)) + "\n\n" + marker).take(cap)
    }
}
