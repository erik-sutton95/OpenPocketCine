package com.opencapture.monitorui

import androidx.compose.ui.graphics.Color
import kotlin.test.Test
import kotlin.test.assertEquals

class MonitorMaterialTest {
    @Test fun densitiesMatchTheSwiftGlassContract() {
        assertEquals(18f, MonitorMaterial.Compact.blurDp)
        assertEquals(18f, MonitorMaterial.Record.blurDp)
        assertEquals(20f, MonitorMaterial.Expanded.blurDp)
        assertEquals(20f, MonitorMaterial.Info.blurDp)
        assertEquals(20f, MonitorMaterial.Delivery.blurDp)
        assertEquals(24f, MonitorMaterial.Zoom.blurDp)
        assertEquals(8f, MonitorMaterial.Scope.blurDp)
        assertEquals(1.25f, MonitorMaterial.Compact.saturation)
        assertEquals(1f, MonitorMaterial.Scope.saturation)
        assertEquals(.52f, MonitorMaterial.Compact.tint.alpha, 0.5f / 255f + 0.000001f)
        assertEquals(.62f, MonitorMaterial.Expanded.tint.alpha, 0.5f / 255f + 0.000001f)
        assertEquals(.82f, MonitorMaterial.Info.tint.alpha, 0.5f / 255f + 0.000001f)
        assertEquals(.86f, MonitorMaterial.Delivery.tint.alpha, 0.5f / 255f + 0.000001f)
        assertEquals(.72f, MonitorMaterial.Zoom.tint.alpha, 0.5f / 255f + 0.000001f)
        assertEquals(.70f, MonitorMaterial.Scope.tint.alpha, 0.5f / 255f + 0.000001f)
        assertEquals(.08f, MonitorMaterial.Record.tint.alpha, 0.5f / 255f + 0.000001f)
    }

    @Test fun hairlinesMatchIosOverlayAlphasAndWidth() {
        assertEquals(0f, MonitorMaterial.Compact.hairline)
        assertEquals(0f, MonitorMaterial.Expanded.hairline)
        assertEquals(.07f, MonitorMaterial.Info.hairline)
        assertEquals(.08f, MonitorMaterial.Delivery.hairline)
        assertEquals(.09f, MonitorMaterial.Zoom.hairline)
        assertEquals(.09f, MonitorMaterial.Scope.hairline)
        assertEquals(.16f, MonitorMaterial.Record.hairline)
        assertEquals(.75f, MonitorMaterial.HAIRLINE_WIDTH_DP)
    }

    @Test fun missingSampleUsesCanvasExceptScopeKeepsOpaqueTint() {
        assertEquals(Color(0xFF08090A), MonitorMaterial.Compact.fallbackFill())
        assertEquals(Color(0xFF08090A), MonitorMaterial.Record.fallbackFill())
        assertEquals(Color(0xFF08090A), MonitorMaterial.Expanded.fallbackFill())
        assertEquals(1f, MonitorMaterial.Scope.fallbackFill().alpha)
        assertEquals(6f / 255f, MonitorMaterial.Scope.fallbackFill().red, 0.001f)
    }

    @Test fun pageTokensMatchIosRaisedBorderAndSecondary() {
        assertEquals(Color(0xFF222425), MonitorPalette.tile)
        assertEquals(.08f, MonitorPalette.border.alpha, 0.5f / 255f + 0.000001f)
        assertEquals(Color(0xFFCFD4D4), MonitorPalette.secondary)
    }
}
