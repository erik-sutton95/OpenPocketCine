package com.opencapture.openpocketcine.assists

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.opencapture.openpocketcine.OperatorPrefs
import com.opencapture.openpocketcine.feed.ScopeAssistBundle
import org.json.JSONArray
import org.json.JSONObject

/**
 * Live-view assist toggles, options, and clean-view pins.
 *
 * [mirror] is the horizontal flip flag. [LiveAssistLayer] never flips the video;
 * [LiveViewScreen] should apply `graphicsLayer { scaleX = if (state.mirror) -1f else 1f }`
 * so the recording and scopes stay unmirrored.
 */
class LiveAssistState(
    encoded: String? = null,
    pinnedNames: Set<String> = OperatorPrefs.DEFAULT_CLEAN_PINS,
    private val onPersist: ((String) -> Unit)? = null,
    private val onPersistPins: ((Set<String>) -> Unit)? = null,
    playbackNames: Set<String> = emptySet(),
    private val onPersistPlayback: ((Set<String>) -> Unit)? = null,
) {
    var lutOn by mutableStateOf(true)
        private set
    var peaking by mutableStateOf(false)
        private set
    var falseColor by mutableStateOf(false)
        private set
    var zebra by mutableStateOf(false)
        private set
    var waveform by mutableStateOf(false)
        private set
    var parade by mutableStateOf(false)
        private set
    var histogram by mutableStateOf(false)
        private set
    var vectorscope by mutableStateOf(false)
        private set
    var trafficLights by mutableStateOf(false)
        private set
    var audioMeters by mutableStateOf(false)
        private set
    var guides by mutableStateOf(false)
        private set
    var grid by mutableStateOf(false)
        private set
    var crosshair by mutableStateOf(false)
        private set

    /**
     * Horizontal flip of the monitored picture. Overlay chrome does not apply this;
     * the video surface owner must.
     */
    var mirror by mutableStateOf(false)
        private set

    /** iOS `splitComparison` — 50/50 log vs LUT. Monitor-only. */
    var splitComparison by mutableStateOf(false)
        private set

    /** iOS `splitVertical` — true is Left / Right, false is Top / Bottom. */
    var splitVertical by mutableStateOf(true)
        private set

    var clean by mutableStateOf(false)
    var pinned by mutableStateOf(parsePins(pinnedNames))

    var guideFamily by mutableStateOf(GuideFamily.FILM)
    var guideAspect by mutableStateOf(GuideAspect.CINEMA)
    var selectedGuides by mutableStateOf(setOf(GuideAspect.CINEMA))
    var guideMask by mutableStateOf(false)

    var gridThirds by mutableStateOf(true)
    var gridPhi by mutableStateOf(false)
    var gridDiagonal by mutableStateOf(false)

    var peakingColor by mutableStateOf(PeakingColor.RED)
    var peakingSensitivity by mutableStateOf(PeakingSense.MED)

    var falseColorScale by mutableStateOf(FalseColorScale.STOPS)
    var falseColorReference by mutableStateOf(true)

    var zebraUnit by mutableStateOf(ZebraUnit.IRE)
    var zebraHighlight by mutableStateOf(true)
    var zebraMidtone by mutableStateOf(true)
    var zebraHighlightIRE by mutableDoubleStateOf(LiveZebra.HIGHLIGHT_IRE)
    var zebraMidtoneIRE by mutableDoubleStateOf(LiveZebra.MIDTONE_IRE)
    var zebraHighlightColor by mutableStateOf(ZebraPaint.WHITE)
    var zebraMidtoneColor by mutableStateOf(ZebraPaint.AMBER)

    var waveMode by mutableStateOf(WaveformMode.RGB)
    var waveBrightness by mutableStateOf(100)
    var waveGuides by mutableStateOf(ScopeGuides())
    var waveScale by mutableDoubleStateOf(1.0)
    var waveCenter by mutableStateOf<StoredCenter?>(null)

    var paradeMode by mutableStateOf(ParadeMode.RGB)
    var paradeBrightness by mutableStateOf(100)
    var paradeGuides by mutableStateOf(ScopeGuides())
    var paradeScale by mutableDoubleStateOf(1.0)
    var paradeCenter by mutableStateOf<StoredCenter?>(null)

    var histoTrafficLights by mutableStateOf(true)
    var histoScale by mutableDoubleStateOf(1.0)
    var histoCenter by mutableStateOf<StoredCenter?>(null)

    var vectorZoom by mutableStateOf(VectorscopeZoom.X1)
    var vectorBrightness by mutableStateOf(100)
    var vectorScale by mutableDoubleStateOf(1.0)
    var vectorCenter by mutableStateOf<StoredCenter?>(null)

    var crushClipCompensation by mutableStateOf(CrushClipCompensation.ZERO)
    var lightsScale by mutableDoubleStateOf(1.0)
    var lightsCenter by mutableStateOf<StoredCenter?>(null)

    /** Last-moved / last-selected is last. Compose and Vulkan draw in this order. */
    var scopeStack by mutableStateOf(defaultScopeStack)
        private set

    var configureTool by mutableStateOf<LiveAssistTool?>(null)

    /** Pressed assist chip, viewport-absolute. iOS `LiveAssistState.longPressAnchor`. */
    var longPressAnchor by mutableStateOf(com.opencapture.openpocketcine.ChromeRect(0f, 0f, 0f, 0f))

    /** OpenZCine `playbackVisibleAssistTools` — independent of the live toolbar. */
    var playbackVisibleTools by mutableStateOf(parsePlayback(playbackNames))
        private set

    /**
     * Latest GLES tap. WAVE / PARADE / HISTO / VECTOR / LIGHTS read this;
     * [lumaHistogram] mirrors native luma counts for tests.
     */
    var scopeBundle by mutableStateOf(ScopeAssistBundle.EMPTY)

    /** Optional 256-bin luminance histogram. Null / all-zero draws empty bins. */
    var lumaHistogram by mutableStateOf<IntArray?>(null)

    fun acceptScopeBundle(bundle: ScopeAssistBundle) {
        scopeBundle = bundle
        lumaHistogram = bundle.samples.histogramLuma
    }

    init {
        if (!encoded.isNullOrBlank()) applyEncoded(encoded)
    }

    fun isOn(tool: LiveAssistTool): Boolean =
        when (tool) {
            LiveAssistTool.LUT -> lutOn
            LiveAssistTool.PEAK -> peaking
            LiveAssistTool.FALSE -> falseColor
            LiveAssistTool.ZEBRA -> zebra
            LiveAssistTool.WAVE -> waveform
            LiveAssistTool.PARADE -> parade
            LiveAssistTool.HISTO -> histogram
            LiveAssistTool.VECTOR -> vectorscope
            LiveAssistTool.LIGHTS -> trafficLights
            LiveAssistTool.AUDIO -> audioMeters
            LiveAssistTool.GUIDES -> guides
            LiveAssistTool.GRID -> grid
            LiveAssistTool.CROSS -> crosshair
            LiveAssistTool.MIRROR -> mirror
        }

    /** Pins filter DISP 2; they never flip [isOn]. */
    fun isVisible(tool: LiveAssistTool): Boolean {
        if (!isOn(tool)) return false
        return if (clean) pinned.contains(tool) else true
    }

    /** Re-arms the last look. The bar chip is the only off (iOS `armLastLUT`). */
    fun armLut() {
        if (lutOn) return
        lutOn = true
        persist()
    }

    fun setSplitComparison(enabled: Boolean, vertical: Boolean = splitVertical) {
        splitComparison = enabled
        splitVertical = vertical
        if (enabled) armLut()
        persist()
    }

    fun toggle(tool: LiveAssistTool) {
        when (tool) {
            LiveAssistTool.LUT -> lutOn = !lutOn
            LiveAssistTool.PEAK -> peaking = !peaking
            LiveAssistTool.FALSE -> falseColor = !falseColor
            LiveAssistTool.ZEBRA -> zebra = !zebra
            LiveAssistTool.WAVE -> waveform = !waveform
            LiveAssistTool.PARADE -> parade = !parade
            LiveAssistTool.HISTO -> histogram = !histogram
            LiveAssistTool.VECTOR -> vectorscope = !vectorscope
            LiveAssistTool.LIGHTS -> trafficLights = !trafficLights
            LiveAssistTool.AUDIO -> audioMeters = !audioMeters
            LiveAssistTool.GUIDES -> {
                guides = !guides
                if (guides && selectedGuides.isEmpty()) selectedGuides = setOf(guideAspect)
            }
            LiveAssistTool.GRID -> grid = !grid
            LiveAssistTool.CROSS -> crosshair = !crosshair
            LiveAssistTool.MIRROR -> mirror = !mirror
        }
        if (tool in stackableScopeTools && isOn(tool)) bringToFront(tool)
        persist()
    }

    fun bringToFront(tool: LiveAssistTool) {
        if (tool !in stackableScopeTools) return
        if (scopeStack.lastOrNull() == tool) return
        scopeStack = scopeStack.filter { it != tool } + tool
        persist()
    }

    fun isPlaybackVisible(tool: LiveAssistTool): Boolean = tool in playbackVisibleTools

    /** LUT / PEAK / FALSE / ZEBRA / scopes — used to gate a processed present path. */
    fun playbackNeedsProcessedFeed(): Boolean =
        playbackVisibleTools.any { it in processedPlaybackTools }

    fun playbackNeedsScopeTap(): Boolean =
        playbackVisibleTools.any { it in stackableScopeTools }

    fun playbackNeedsLookOverlay(): Boolean =
        playbackVisibleTools.any { it in lookOverlayTools }

    fun togglePlayback(tool: LiveAssistTool) {
        playbackVisibleTools =
            if (tool in playbackVisibleTools) playbackVisibleTools - tool else playbackVisibleTools + tool
        onPersistPlayback?.invoke(playbackVisibleTools.map { it.name }.toSet())
    }

    fun togglePin(tool: LiveAssistTool) {
        if (tool !in LiveAssistTool.cleanPinCases) return
        pinned = if (tool in pinned) pinned - tool else pinned + tool
        onPersistPins?.invoke(pinned.map { it.name }.toSet())
    }

    fun cycleGuide() {
        val all = GuideAspect.ratios(guideFamily)
        val idx = all.indexOf(guideAspect)
        guideAspect = if (idx < 0) all.firstOrNull() ?: GuideAspect.CINEMA else all[(idx + 1) % all.size]
        selectedGuides = setOf(guideAspect)
        guides = true
        persist()
    }

    fun toggleGuide(aspect: GuideAspect) {
        selectedGuides =
            if (aspect in selectedGuides) selectedGuides - aspect else selectedGuides + aspect
        guideAspect = aspect
        guides = selectedGuides.isNotEmpty()
        persist()
    }

    fun updateGuideFamily(family: GuideFamily) {
        guideFamily = family
        persist()
    }

    fun updateGuideMask(on: Boolean) {
        guideMask = on
        persist()
    }

    fun setGridOption(thirds: Boolean = gridThirds, phi: Boolean = gridPhi, diagonal: Boolean = gridDiagonal) {
        gridThirds = thirds
        gridPhi = phi
        gridDiagonal = diagonal
        persist()
    }

    fun setPeaking(color: PeakingColor = peakingColor, sense: PeakingSense = peakingSensitivity) {
        peakingColor = color
        peakingSensitivity = sense
        persist()
    }

    fun setFalseColor(scale: FalseColorScale = falseColorScale, reference: Boolean = falseColorReference) {
        falseColorScale = scale
        falseColorReference = reference
        if (reference) falseColor = true
        persist()
    }

    fun setZebraHighlight(enabled: Boolean = zebraHighlight, ire: Double = zebraHighlightIRE, color: ZebraPaint = zebraHighlightColor) {
        zebraHighlight = enabled
        zebraHighlightIRE = ire.coerceIn(0.0, 100.0)
        zebraHighlightColor = color
        persist()
    }

    fun setZebraMidtone(enabled: Boolean = zebraMidtone, ire: Double = zebraMidtoneIRE, color: ZebraPaint = zebraMidtoneColor) {
        zebraMidtone = enabled
        zebraMidtoneIRE = ire.coerceIn(0.0, 100.0)
        zebraMidtoneColor = color
        persist()
    }

    fun updateZebraUnit(unit: ZebraUnit) {
        zebraUnit = unit
        persist()
    }

    fun setWaveform(mode: WaveformMode = waveMode, brightness: Int = waveBrightness, guides: ScopeGuides = waveGuides, scale: Double = waveScale) {
        waveMode = mode
        waveBrightness = brightness.coerceIn(0, 200)
        waveGuides = guides
        waveScale = MovablePanelMath.clampedScale(scale)
        persist()
    }

    fun setParade(mode: ParadeMode = paradeMode, brightness: Int = paradeBrightness, guides: ScopeGuides = paradeGuides, scale: Double = paradeScale) {
        paradeMode = mode
        paradeBrightness = brightness.coerceIn(0, 200)
        paradeGuides = guides
        paradeScale = MovablePanelMath.clampedScale(scale)
        persist()
    }

    fun setHistogram(traffic: Boolean = histoTrafficLights, compensation: CrushClipCompensation = crushClipCompensation, scale: Double = histoScale) {
        histoTrafficLights = traffic
        crushClipCompensation = compensation
        histoScale = MovablePanelMath.clampedScale(scale)
        persist()
    }

    fun setVectorscope(zoom: VectorscopeZoom = vectorZoom, brightness: Int = vectorBrightness, scale: Double = vectorScale) {
        vectorZoom = zoom
        vectorBrightness = brightness.coerceIn(0, 200)
        vectorScale = MovablePanelMath.clampedScale(scale)
        persist()
    }

    fun setCompensation(value: CrushClipCompensation) {
        crushClipCompensation = value
        persist()
    }

    fun storeCenter(tool: LiveAssistTool, center: StoredCenter) {
        when (tool) {
            LiveAssistTool.WAVE -> waveCenter = center
            LiveAssistTool.PARADE -> paradeCenter = center
            LiveAssistTool.HISTO -> histoCenter = center
            LiveAssistTool.VECTOR -> vectorCenter = center
            LiveAssistTool.LIGHTS -> lightsCenter = center
            else -> return
        }
        persist()
    }

    fun setScale(tool: LiveAssistTool, scale: Double) {
        val clamped = MovablePanelMath.clampedScale(scale)
        when (tool) {
            LiveAssistTool.WAVE -> waveScale = clamped
            LiveAssistTool.PARADE -> paradeScale = clamped
            LiveAssistTool.HISTO -> histoScale = clamped
            LiveAssistTool.VECTOR -> vectorScale = clamped
            LiveAssistTool.LIGHTS -> lightsScale = clamped
            else -> return
        }
        persist()
    }

    /** Apply a visible-tool set without writing prefs (live chrome adapter). */
    fun syncVisible(tools: Set<LiveAssistTool>, guideRatio: Float? = null) {
        lutOn = LiveAssistTool.LUT in tools
        peaking = LiveAssistTool.PEAK in tools
        falseColor = LiveAssistTool.FALSE in tools
        zebra = LiveAssistTool.ZEBRA in tools
        waveform = LiveAssistTool.WAVE in tools
        parade = LiveAssistTool.PARADE in tools
        histogram = LiveAssistTool.HISTO in tools
        vectorscope = LiveAssistTool.VECTOR in tools
        trafficLights = LiveAssistTool.LIGHTS in tools
        audioMeters = LiveAssistTool.AUDIO in tools
        guides = LiveAssistTool.GUIDES in tools
        grid = LiveAssistTool.GRID in tools
        crosshair = LiveAssistTool.CROSS in tools
        mirror = LiveAssistTool.MIRROR in tools
        if (guideRatio != null && guideRatio > 0f) {
            guideAspect = GuideAspect.entries.minBy { kotlin.math.abs(it.ratio - guideRatio) }
            selectedGuides = setOf(guideAspect)
        }
    }

    fun persist() {
        onPersist?.invoke(encoded())
    }

    fun encoded(): String {
        val tools = JSONArray()
        for (tool in LiveAssistTool.entries) {
            if (isOn(tool)) tools.put(tool.name)
        }
        val guidesJson = JSONArray()
        for (g in selectedGuides) guidesJson.put(g.label)
        return JSONObject()
            .put("tools", tools)
            .put("guideAspect", guideAspect.label)
            .put("guideFamily", guideFamily.label)
            .put("selectedGuides", guidesJson)
            .put("guideMask", guideMask)
            .put("gridThirds", gridThirds)
            .put("gridPhi", gridPhi)
            .put("gridDiagonal", gridDiagonal)
            .put("peakingColor", peakingColor.label)
            .put("peakingSensitivity", peakingSensitivity.label)
            .put("falseColorScale", falseColorScale.persisted)
            .put("falseColorReference", falseColorReference)
            .put("zebraUnit", zebraUnit.persisted)
            .put("zebraHighlight", zebraHighlight)
            .put("zebraMidtone", zebraMidtone)
            .put("zebraHighlightIRE", zebraHighlightIRE)
            .put("zebraMidtoneIRE", zebraMidtoneIRE)
            .put("zebraHighlightColor", zebraHighlightColor.label)
            .put("zebraMidtoneColor", zebraMidtoneColor.label)
            .put("lutArmed", lutOn)
            .put("splitComparison", splitComparison)
            .put("splitVertical", splitVertical)
            .put("crushClipCompensation", crushClipCompensation.raw)
            .put("waveMode", waveMode.label)
            .put("waveBrightness", waveBrightness)
            .put("waveGuides", encodeGuides(waveGuides))
            .put("waveScale", waveScale)
            .put("waveCenter", encodeCenter(waveCenter))
            .put("paradeMode", paradeMode.label)
            .put("paradeBrightness", paradeBrightness)
            .put("paradeGuides", encodeGuides(paradeGuides))
            .put("paradeScale", paradeScale)
            .put("paradeCenter", encodeCenter(paradeCenter))
            .put("histoTrafficLights", histoTrafficLights)
            .put("histoScale", histoScale)
            .put("histoCenter", encodeCenter(histoCenter))
            .put("vectorZoom", vectorZoom.label)
            .put("vectorBrightness", vectorBrightness)
            .put("vectorScale", vectorScale)
            .put("vectorCenter", encodeCenter(vectorCenter))
            .put("lightsScale", lightsScale)
            .put("lightsCenter", encodeCenter(lightsCenter))
            .put("scopeStack", JSONArray(scopeStack.map { it.name }))
            .toString()
    }

    private fun applyEncoded(raw: String) {
        val obj = runCatching { JSONObject(raw) }.getOrNull() ?: return
        val on = buildSet {
            val tools = obj.optJSONArray("tools") ?: return@buildSet
            for (i in 0 until tools.length()) {
                LiveAssistTool.fromPersisted(tools.optString(i))?.let { add(it) }
            }
        }
        peaking = LiveAssistTool.PEAK in on
        falseColor = LiveAssistTool.FALSE in on
        zebra = LiveAssistTool.ZEBRA in on
        waveform = LiveAssistTool.WAVE in on
        parade = LiveAssistTool.PARADE in on
        histogram = LiveAssistTool.HISTO in on
        vectorscope = LiveAssistTool.VECTOR in on
        trafficLights = LiveAssistTool.LIGHTS in on
        audioMeters = LiveAssistTool.AUDIO in on
        guides = LiveAssistTool.GUIDES in on
        grid = LiveAssistTool.GRID in on
        crosshair = LiveAssistTool.CROSS in on
        mirror = LiveAssistTool.MIRROR in on
        lutOn = if (obj.has("lutArmed")) obj.optBoolean("lutArmed", true) else LiveAssistTool.LUT in on
        splitComparison = obj.optBoolean("splitComparison", false)
        splitVertical = obj.optBoolean("splitVertical", true)
        guideAspect = GuideAspect.fromPersisted(obj.optString("guideAspect", GuideAspect.CINEMA.label))
        guideFamily = GuideFamily.fromPersisted(obj.optString("guideFamily", GuideFamily.FILM.label))
        val restored = buildSet {
            val arr = obj.optJSONArray("selectedGuides") ?: return@buildSet
            for (i in 0 until arr.length()) add(GuideAspect.fromPersisted(arr.optString(i)))
        }
        selectedGuides = restored.ifEmpty { setOf(guideAspect) }
        guideMask = obj.optBoolean("guideMask", false)
        gridThirds = obj.optBoolean("gridThirds", true)
        gridPhi = obj.optBoolean("gridPhi", false)
        gridDiagonal = obj.optBoolean("gridDiagonal", false)
        peakingColor = PeakingColor.fromPersisted(obj.optString("peakingColor", PeakingColor.RED.label))
        peakingSensitivity = PeakingSense.fromPersisted(obj.optString("peakingSensitivity", PeakingSense.MED.label))
        falseColorScale = FalseColorScale.fromPersisted(obj.optString("falseColorScale", FalseColorScale.STOPS.persisted))
        falseColorReference = obj.optBoolean("falseColorReference", true)
        zebraUnit = ZebraUnit.fromPersisted(obj.optString("zebraUnit", ZebraUnit.IRE.persisted))
        zebraHighlight = obj.optBoolean("zebraHighlight", true)
        zebraMidtone = obj.optBoolean("zebraMidtone", true)
        zebraHighlightIRE = obj.optDouble("zebraHighlightIRE", LiveZebra.HIGHLIGHT_IRE)
        zebraMidtoneIRE = obj.optDouble("zebraMidtoneIRE", LiveZebra.MIDTONE_IRE)
        zebraHighlightColor = ZebraPaint.fromPersisted(obj.optString("zebraHighlightColor", ZebraPaint.WHITE.label))
        zebraMidtoneColor = ZebraPaint.fromPersisted(obj.optString("zebraMidtoneColor", ZebraPaint.AMBER.label))
        crushClipCompensation = CrushClipCompensation.fromRaw(obj.optInt("crushClipCompensation", 0))
        waveMode = WaveformMode.fromPersisted(obj.optString("waveMode", WaveformMode.RGB.label))
        waveBrightness = obj.optInt("waveBrightness", 100).coerceIn(0, 200)
        waveGuides = decodeGuides(obj.optJSONObject("waveGuides"))
        waveScale = MovablePanelMath.clampedScale(obj.optDouble("waveScale", 1.0))
        waveCenter = decodeCenter(obj.optJSONObject("waveCenter"))
        paradeMode = ParadeMode.fromPersisted(obj.optString("paradeMode", ParadeMode.RGB.label))
        paradeBrightness = obj.optInt("paradeBrightness", 100).coerceIn(0, 200)
        paradeGuides = decodeGuides(obj.optJSONObject("paradeGuides"))
        paradeScale = MovablePanelMath.clampedScale(obj.optDouble("paradeScale", 1.0))
        paradeCenter = decodeCenter(obj.optJSONObject("paradeCenter"))
        histoTrafficLights = obj.optBoolean("histoTrafficLights", true)
        histoScale = MovablePanelMath.clampedScale(obj.optDouble("histoScale", 1.0))
        histoCenter = decodeCenter(obj.optJSONObject("histoCenter"))
        vectorZoom = VectorscopeZoom.fromPersisted(obj.optString("vectorZoom", VectorscopeZoom.X1.label))
        vectorBrightness = obj.optInt("vectorBrightness", 100).coerceIn(0, 200)
        vectorScale = MovablePanelMath.clampedScale(obj.optDouble("vectorScale", 1.0))
        vectorCenter = decodeCenter(obj.optJSONObject("vectorCenter"))
        lightsScale = MovablePanelMath.clampedScale(obj.optDouble("lightsScale", 1.0))
        lightsCenter = decodeCenter(obj.optJSONObject("lightsCenter"))
        scopeStack = decodeScopeStack(obj.optJSONArray("scopeStack"))
    }

    companion object {
        val defaultPinned: Set<LiveAssistTool> =
            setOf(LiveAssistTool.LUT, LiveAssistTool.PEAK, LiveAssistTool.MIRROR)

        val stackableScopeTools: List<LiveAssistTool> =
            listOf(
                LiveAssistTool.WAVE,
                LiveAssistTool.PARADE,
                LiveAssistTool.VECTOR,
                LiveAssistTool.HISTO,
                LiveAssistTool.LIGHTS,
            )

        val defaultScopeStack: List<LiveAssistTool>
            get() = stackableScopeTools

        val lookOverlayTools: Set<LiveAssistTool> =
            setOf(
                LiveAssistTool.LUT,
                LiveAssistTool.PEAK,
                LiveAssistTool.FALSE,
                LiveAssistTool.ZEBRA,
            )

        val processedPlaybackTools: Set<LiveAssistTool> =
            setOf(
                LiveAssistTool.LUT,
                LiveAssistTool.PEAK,
                LiveAssistTool.FALSE,
                LiveAssistTool.ZEBRA,
                LiveAssistTool.WAVE,
                LiveAssistTool.PARADE,
                LiveAssistTool.HISTO,
                LiveAssistTool.VECTOR,
                LiveAssistTool.LIGHTS,
            )

        fun from(context: Context): LiveAssistState {
            val app = context.applicationContext
            return LiveAssistState(
                encoded = OperatorPrefs.assistEncoded(app),
                pinnedNames = OperatorPrefs.cleanViewPinnedTools(app),
                onPersist = { OperatorPrefs.setAssistEncoded(app, it) },
                onPersistPins = { OperatorPrefs.setCleanViewPinnedTools(app, it) },
                playbackNames = OperatorPrefs.playbackVisibleAssistTools(app),
                onPersistPlayback = { OperatorPrefs.setPlaybackVisibleAssistTools(app, it) },
            )
        }

        private fun parsePins(names: Set<String>): Set<LiveAssistTool> {
            val parsed = names.mapNotNull(LiveAssistTool::fromPersisted).toSet()
            return parsed.ifEmpty { defaultPinned }
        }

        private fun parsePlayback(names: Set<String>): Set<LiveAssistTool> =
            names.mapNotNull(LiveAssistTool::fromPersisted).toSet()

        private fun encodeGuides(guides: ScopeGuides): JSONObject =
            JSONObject().put("clip", guides.clip).put("crush", guides.crush).put("middle", guides.middle)

        private fun decodeGuides(obj: JSONObject?): ScopeGuides {
            if (obj == null) return ScopeGuides()
            return ScopeGuides(
                clip = obj.optBoolean("clip", true),
                crush = obj.optBoolean("crush", true),
                middle = obj.optBoolean("middle", true),
            )
        }

        private fun encodeCenter(center: StoredCenter?): Any =
            if (center == null) {
                JSONObject.NULL
            } else {
                JSONObject().put("xFraction", center.xFraction).put("yFraction", center.yFraction)
            }

        private fun decodeCenter(obj: JSONObject?): StoredCenter? {
            if (obj == null) return null
            return StoredCenter(obj.optDouble("xFraction", 0.5), obj.optDouble("yFraction", 0.5))
        }

        private fun decodeScopeStack(arr: JSONArray?): List<LiveAssistTool> {
            if (arr == null) return defaultScopeStack
            val seen = LinkedHashSet<LiveAssistTool>()
            for (i in 0 until arr.length()) {
                val tool = LiveAssistTool.fromPersisted(arr.optString(i)) ?: continue
                if (tool in stackableScopeTools) seen += tool
            }
            return seen.toList() + stackableScopeTools.filter { it !in seen }
        }
    }
}
