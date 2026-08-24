package com.opencapture.openpocketcine

import kotlin.math.max
import kotlin.math.min

/**
 * Lockstep with Swift `GimbalCluster`. Stick, zoom chip, and (later) gimbal
 * controls as one parking spot. Follow / speed / A·B·C attach to [controls]
 * without moving the stick.
 */
data class GimbalCluster(
    val stick: ChromeRect,
    val zoom: ChromeRect,
    val controls: ChromeRect,
) {
    val bounds: ChromeRect
        get() {
            var minX = min(stick.minX, zoom.minX)
            var minY = min(stick.minY, zoom.minY)
            var maxX = max(stick.maxX, zoom.maxX)
            var maxY = max(stick.maxY, zoom.maxY)
            if (controls.width > 1f) {
                minX = min(minX, controls.minX)
                minY = min(minY, controls.minY)
                maxX = max(maxX, controls.maxX)
                maxY = max(maxY, controls.maxY)
            }
            return ChromeRect(minX, minY, max(0f, maxX - minX), max(0f, maxY - minY))
        }

    fun offset(dx: Float, dy: Float): GimbalCluster =
        GimbalCluster(stick.offset(dx, dy), zoom.offset(dx, dy), controls.offset(dx, dy))

    companion object {
        const val STICK = 88f
        const val ZOOM = 44f
        const val GAP = 8f
        const val INSET = 16f

        fun inTrailingBottom(
            well: ChromeRect,
            floorY: Float,
            canvasMaxY: Float,
            avoid: ChromeRect? = null,
            stickSize: Float = STICK,
            zoomSize: Float = ZOOM,
            gap: Float = GAP,
            inset: Float = INSET,
            controlsWidth: Float = 0f,
        ): GimbalCluster {
            val stickSize = max(0f, stickSize)
            val inset = max(0f, inset)
            val canvasFloor = canvasMaxY - inset
            val stickMaxY = min(min(floorY, well.maxY - inset), canvasFloor)
            var stickY = max(well.minY + inset, stickMaxY - stickSize)
            var stickX = well.maxX - inset - stickSize
            stickX = min(max(stickX, well.minX + inset), max(well.minX, well.maxX - inset - stickSize))
            var cluster =
                stacked(
                    stickX = stickX,
                    stickY = stickY,
                    well = well,
                    stickSize = stickSize,
                    zoomSize = zoomSize,
                    gap = gap,
                    controlsWidth = controlsWidth,
                )
            cluster = dodge(cluster, avoid, well, gap, inset)
            return cluster
        }

        fun belowWell(
            well: ChromeRect,
            floorY: Float,
            stickSize: Float = STICK,
            zoomSize: Float = ZOOM,
            gap: Float = GAP,
            inset: Float = INSET,
            controlsWidth: Float = 0f,
        ): GimbalCluster {
            val stickSize = max(0f, stickSize)
            val zoomSize = max(0f, zoomSize)
            val gap = max(0f, gap)
            val inset = max(0f, inset)
            val ceiling = well.maxY + gap
            val stickY = max(ceiling + zoomSize + gap, floorY - inset - stickSize)
            val stickX = max(well.minX, well.maxX - inset - stickSize)
            return stacked(
                stickX = stickX,
                stickY = stickY,
                well = well,
                stickSize = stickSize,
                zoomSize = zoomSize,
                gap = gap,
                controlsWidth = controlsWidth,
                zoomFloor = ceiling,
            )
        }

        private fun stacked(
            stickX: Float,
            stickY: Float,
            well: ChromeRect,
            stickSize: Float,
            zoomSize: Float,
            gap: Float,
            controlsWidth: Float,
            zoomFloor: Float? = null,
        ): GimbalCluster {
            val zoomSize = max(0f, zoomSize)
            val gap = max(0f, gap)
            val controlsWidth = max(0f, controlsWidth)
            val stick = ChromeRect(stickX, stickY, stickSize, stickSize)
            val zoomX = min(max(well.minX, stick.maxX - zoomSize), max(well.minX, well.maxX - zoomSize))
            val stackedY = stick.minY - gap - zoomSize
            val zoomY = max(zoomFloor ?: well.minY, stackedY)
            val zoom = ChromeRect(zoomX, zoomY, zoomSize, zoomSize)
            val controls =
                if (controlsWidth > 0f) {
                    ChromeRect(stick.minX - gap - controlsWidth, stick.minY, controlsWidth, stickSize)
                } else {
                    ChromeRect(stick.minX, stick.minY, 0f, 0f)
                }
            return GimbalCluster(stick, zoom, controls)
        }

        private fun dodge(
            cluster: GimbalCluster,
            avoid: ChromeRect?,
            well: ChromeRect,
            gap: Float,
            inset: Float,
        ): GimbalCluster {
            if (avoid == null || avoid.width <= 1f || avoid.height <= 1f) return cluster
            val padded = avoid.inset(-gap, -gap)
            if (!cluster.bounds.intersects(padded)) return cluster
            // Width-constrained tablets park record on the canvas floor. Lift
            // the cluster above it and keep the trailing edge.
            val liftedMaxY = avoid.minY - gap
            val liftedMinY = liftedMaxY - cluster.bounds.height
            if (liftedMinY >= well.minY + inset) {
                return cluster.offset(0f, liftedMaxY - cluster.bounds.maxY)
            }
            val dx =
                if (avoid.midX >= cluster.bounds.midX) {
                    avoid.minX - gap - cluster.bounds.maxX
                } else {
                    avoid.maxX + gap - cluster.bounds.minX
                }
            var next = cluster.offset(dx, 0f)
            val minX = well.minX + inset
            if (next.bounds.minX < minX) next = next.offset(minX - next.bounds.minX, 0f)
            val maxX = well.maxX - inset
            if (next.bounds.maxX > maxX) next = next.offset(maxX - next.bounds.maxX, 0f)
            return next
        }
    }
}

private fun ChromeRect.offset(dx: Float, dy: Float): ChromeRect = copy(x = x + dx, y = y + dy)
