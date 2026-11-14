package dev.qs.amapmapsflutterqs.amap_maps_flutter_qs

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/*
 * OverlayCallBuffer（mapLoaded 前覆盖物调用缓冲）单元测试。
 *
 * 纯状态机测试，不依赖 Android 运行时。构建后在 example/android/ 目录运行：
 * ~/.gradle/wrapper/dists/gradle-9.1.0-all/<hash>/bin/gradle
 *   :amap_maps_flutter_qs:testDebugUnitTest
 *
 * 锁定的核心行为（0.2.4 修复的回归保护）：
 * 1. FIFO 保序 —— 「add 后 remove」回放顺序不可交换；
 * 2. drain 一次性取出并清空；
 * 3. clear 直接丢弃（map 销毁路径）；
 * 4. drain 空缓冲返回空列表且不抛异常。
 */
internal class OverlayCallBufferTest {

    @Test
    fun add_keepsFifoOrder() {
        val buffer = OverlayCallBuffer()
        buffer.add("map#updateMarkers", mapOf("toAdd" to listOf("m1")))
        buffer.add("map#updateMarkers", mapOf("toRemove" to listOf("m1")))
        buffer.add("map#showInfoWindow", "m1")

        assertEquals(3, buffer.size)
        val drained = buffer.drain()
        assertEquals(
            listOf(
                "map#updateMarkers" to mapOf("toAdd" to listOf("m1")),
                "map#updateMarkers" to mapOf("toRemove" to listOf("m1")),
                "map#showInfoWindow" to "m1",
            ),
            drained,
        )
    }

    @Test
    fun drain_emptiesBuffer_soSecondDrainReturnsNothing() {
        val buffer = OverlayCallBuffer()
        buffer.add("map#updateCircles", null)
        assertEquals(1, buffer.drain().size)
        assertTrue(buffer.isEmpty())
        assertTrue(buffer.drain().isEmpty())
    }

    @Test
    fun clear_discardsPendingCalls() {
        val buffer = OverlayCallBuffer()
        buffer.add("map#updatePolylines", emptyList<Any>())
        buffer.add("map#updatePolygons", emptyList<Any>())
        buffer.clear()
        assertTrue(buffer.isEmpty())
        assertEquals(0, buffer.size)
        assertTrue(buffer.drain().isEmpty())
    }

    @Test
    fun drain_onEmptyBuffer_isSafe() {
        val buffer = OverlayCallBuffer()
        assertTrue(buffer.drain().isEmpty())
    }

    @Test
    fun add_acceptsNullAndArbitraryArgumentTypes() {
        val buffer = OverlayCallBuffer()
        buffer.add("map#updateMarkers", null)
        buffer.add("map#hideInfoWindow", "m1")
        val drained = buffer.drain()
        assertEquals("map#updateMarkers" to null, drained[0])
        assertEquals("map#hideInfoWindow" to "m1", drained[1])
    }
}
