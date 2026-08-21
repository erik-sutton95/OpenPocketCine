package com.opencapture.openpocketcine

import androidx.compose.ui.text.font.FontWeight
import kotlin.test.Test
import kotlin.test.assertEquals

/** Pins Android `LiveType.ui` to iOS `LiveType.swift` family mapping. */
class LiveTypeTest {
    @Test
    fun roundedTitlesUseSora() {
        assertEquals(OpcFonts.sora, LiveType.ui(30f, FontWeight.Bold, LiveTypeDesign.Rounded).fontFamily)
        assertEquals(OpcFonts.sora, LiveType.ui(16f, FontWeight.SemiBold, LiveTypeDesign.Rounded).fontFamily)
        assertEquals(OpcFonts.sora, LiveType.ui(16f, FontWeight.Normal, LiveTypeDesign.Rounded).fontFamily)
        assertEquals(OpcFonts.sora, LiveType.ui(10f, FontWeight.Bold, LiveTypeDesign.Rounded).fontFamily)
    }

    @Test
    fun roundedBodyStaysPlex() {
        assertEquals(OpcFonts.plex, LiveType.ui(13f, FontWeight.Normal, LiveTypeDesign.Rounded).fontFamily)
        assertEquals(OpcFonts.plex, LiveType.ui(12f, FontWeight.Medium, LiveTypeDesign.Rounded).fontFamily)
    }

    @Test
    fun defaultDesignUsesSoraOnlyForLargeTitles() {
        assertEquals(OpcFonts.sora, LiveType.ui(17f, FontWeight.SemiBold).fontFamily)
        assertEquals(OpcFonts.plex, LiveType.ui(16f, FontWeight.SemiBold).fontFamily)
        assertEquals(OpcFonts.plex, LiveType.ui(12f, FontWeight.Bold).fontFamily)
    }

    @Test
    fun displayIsSora() {
        assertEquals(OpcFonts.sora, LiveType.display(24f).fontFamily)
        assertEquals(OpcFonts.sora, LiveType.title(24f).fontFamily)
        assertEquals(OpcFonts.plex, LiveType.text(16f).fontFamily)
    }
}
