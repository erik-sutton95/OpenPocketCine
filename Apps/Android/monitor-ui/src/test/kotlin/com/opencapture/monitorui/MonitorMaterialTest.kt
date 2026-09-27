package com.opencapture.monitorui

import androidx.compose.ui.graphics.Color
import kotlin.test.Test
import kotlin.test.assertEquals

class MonitorMaterialTest {
    @Test fun missingSampleUsesCanvasExceptScopeKeepsOpaqueTint() {
        assertEquals(Color(0xFF08090A), MonitorMaterial.Compact.fallbackFill())
        assertEquals(Color(0xFF08090A), MonitorMaterial.Record.fallbackFill())
        assertEquals(Color(0xFF08090A), MonitorMaterial.Expanded.fallbackFill())
        assertEquals(1f, MonitorMaterial.Scope.fallbackFill().alpha)
        assertEquals(6f / 255f, MonitorMaterial.Scope.fallbackFill().red, 0.001f)
    }
}
