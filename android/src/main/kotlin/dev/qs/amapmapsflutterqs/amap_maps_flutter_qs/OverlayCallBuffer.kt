package dev.qs.amapmapsflutterqs.amap_maps_flutter_qs

/// mapLoaded 前覆盖物类调用的缓冲区（纯状态机，不依赖 Android/AMap，可 JVM 单测）。
///
/// 背景：高德 SDK 在地图引擎初始化完成前调用 addMarker/addPolygon 等会静默
/// 丢弃覆盖物（社区反复踩坑确认）；而本插件的 mapCreated 在 PlatformView
/// 构造时立即回发，早于引擎就绪。Dart 侧「onMapCreated 里立刻建覆盖物」或
/// 「带初始覆盖物创建地图」的调用都会落进该窗口 —— 必须缓冲到 mapLoaded
/// 再回放，否则覆盖物不显示。
///
/// 语义：
/// - FIFO 保序：先入队的调用先回放（「add 后 remove」不可交换）；
/// - [drain] 一次性取出并清空，mapLoaded 回调中调用；
/// - [clear] 直接丢弃，map 销毁时使用，防止回放到已释放的地图。
/// 通道调用与 mapLoaded 回调均在主线程，无并发问题。
internal class OverlayCallBuffer {

    private val calls = ArrayList<Pair<String, Any?>>()

    val size: Int get() = calls.size

    fun isEmpty(): Boolean = calls.isEmpty()

    /// 入缓冲（保序）。
    fun add(method: String, arguments: Any?) {
        calls.add(method to arguments)
    }

    /// 取出全部缓冲调用并清空（保持入队顺序）。
    fun drain(): List<Pair<String, Any?>> {
        val result = ArrayList(calls)
        calls.clear()
        return result
    }

    /// 丢弃全部缓冲调用。
    fun clear() = calls.clear()
}
