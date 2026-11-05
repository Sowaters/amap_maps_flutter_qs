package dev.qs.amapmapsflutterqs.amap_maps_flutter_qs

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Point
import android.util.Log
import android.util.LruCache
import android.util.TypedValue
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import com.amap.api.maps.AMap
import com.amap.api.maps.CameraUpdate
import com.amap.api.maps.CameraUpdateFactory
import com.amap.api.maps.MapView
import com.amap.api.maps.model.BitmapDescriptor
import com.amap.api.maps.model.BitmapDescriptorFactory
import com.amap.api.maps.model.CameraPosition
import com.amap.api.maps.model.Circle
import com.amap.api.maps.model.CircleOptions
import com.amap.api.maps.model.CustomMapStyleOptions
import com.amap.api.maps.model.LatLng
import com.amap.api.maps.model.LatLngBounds
import com.amap.api.maps.model.Marker
import com.amap.api.maps.model.MarkerOptions
import com.amap.api.maps.model.MyLocationStyle
import com.amap.api.maps.model.Polygon
import com.amap.api.maps.model.PolygonOptions
import com.amap.api.maps.model.Polyline
import com.amap.api.maps.model.PolylineOptions
import io.flutter.FlutterInjector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import java.io.ByteArrayOutputStream
import java.security.MessageDigest

/// 承载高德 [MapView] 的 PlatformView（Hybrid Composition 模式）。
///
/// 每个实例持有独立通道 `amap_maps_flutter_qs/map#<mapId>`，
/// mapId 由 Dart 侧通过 creationParams 传入，保证两端一致。
///
/// 覆盖物同步：Dart 侧差量 diff（MarkerUpdates 模式）后下发
/// `toAdd / toUpdate / toRemove`，原生端按 id 增删改。
/// MVP 策略：update 一律按「删旧 + 建新」处理（id 不变），
/// 差量已保证只重建变更对象；原地更新（setPosition 等）为后续优化项。
class AMapPlatformView(
    context: Context,
    binaryMessenger: BinaryMessenger,
    creationParams: Map<*, *>,
) : PlatformView, MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "AMapPlatformView"

        /// content 模式气泡的占位文本：零宽空格（U+200B）。
        /// SDK 点击管线要求 title/snippet 非空才会调 InfoWindowAdapter，
        /// 部分版本判断前会 trim —— 普通空格会被 trim 成空串仍判为空，
        /// 零宽空格不可见且 trim 不掉（String.trim 只剥 <= U+0020 的字符）
        private const val INFO_WINDOW_PLACEHOLDER = "\u200B"

        /// 全世界可视矩形，等效于"无限制"。
        /// 解除 limitBounds 时不用 setMapStatusLimits(null)——空值语义在 SDK
        /// 内部不可靠（iOS 侧曾因空/零矩形被钳制到世界原点导致蓝屏），
        /// 对齐 iOS 修复方案（MAMapSizeWorld）改用全世界矩形。
        private val WORLD_BOUNDS = LatLngBounds(
            LatLng(-85.05112878, -180.0),
            LatLng(85.05112878, 180.0),
        )
    }

    /// mapId 缺失/非法时直接 fail-fast：静默回退 -1 会让多个异常实例
    /// 在静态注册表中互相覆盖、共用同一通道名，排查远比创建失败困难。
    private val mapId: Int = (creationParams["mapId"] as? Number)?.toInt()
        ?: throw IllegalArgumentException("AMapPlatformView: creationParams missing valid mapId")
    private val appContext: Context = context.applicationContext
    private val mapView = MapView(context)

    /// 冻结截图层：pop 转场开始时把最后画面定格为静态图并立即隐藏 GLSurfaceView，
    /// 让 GL 层的异步销毁（surface/EGL 时序差）发生在用户还看着地图页的阶段，
    /// 根治 HC 模式下"返回后地图残帧叠现一闪而过"。转场取消时解冻恢复。
    private val freezeView = ImageView(context).apply { visibility = View.GONE }

    /// 对外暴露的 PlatformView 根容器：GLSurfaceView（活地图）+ 截图层。
    private val container = FrameLayout(context).apply {
        addView(
            mapView,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
        addView(
            freezeView,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
    }

    private val amap: AMap = mapView.map
    private val channel = MethodChannel(
        binaryMessenger,
        "${AmapMapsFlutterQsPlugin.MAIN_CHANNEL}/map#$mapId",
    )
    private var disposed = false

    /// 地图是否已冻结（截图接管显示）。转场取消时解冻。
    private var frozen = false

    // ---- 覆盖物注册表：Dart 侧 id -> 原生对象 ----
    private val markerById = LinkedHashMap<String, Marker>()
    private val polylineById = LinkedHashMap<String, Polyline>()
    private val polygonById = LinkedHashMap<String, Polygon>()
    private val circleById = LinkedHashMap<String, Circle>()

    /// 反向索引：SDK 原生 marker id -> Dart 侧 id。
    /// 点击/拖拽/气泡渲染等回调按 native id 反查频率高，避免每次 O(n) 遍历 markerById。
    private val markerIdByNativeId = HashMap<String, String>()

    /// 当前显示气泡的 marker id（tap-to-dismiss 追踪）。
    /// Android SDK 的气泡不会因点击地图空白处自动关闭（iOS 原生为 deselect
    /// 语义），由插件自行追踪、在地图点击时主动关闭，对齐 iOS 行为。
    private var shownInfoWindowMarkerId: String? = null

    // 自定义气泡内容：Dart 侧 id -> 气泡图片
    private val customCalloutById = HashMap<String, Bitmap>()

    /// 图标描述缓存：key -> 已构建的 BitmapDescriptor。
    ///
    /// 大量 Marker（几百~几千）共用同一图标时，无缓存意味着每个 marker
    /// 每次新增/更新都要 decodeByteArray + fromBitmap（bytes 类型），既慢
    /// 又重复产生位图内存。按 key 缓存后同图标只构建一次。
    /// 上限 64 条：单地图图标种类远小于 marker 数量，LRU 防极端场景膨胀。
    private val iconCache = object : LruCache<String, BitmapDescriptor>(64) {}

    /// bytes 图标的缓存 key：内容 MD5 摘要（128 位，非加密用途，足够防碰撞）。
    private fun ByteArray.cacheKey(): String {
        val digest = MessageDigest.getInstance("MD5").digest(this)
        return "bytes:" + digest.joinToString("") { "%02x".format(it) }
    }

    init {
        channel.setMethodCallHandler(this)
        AmapMapsFlutterQsPlugin.registerView(mapId, this)

        applyInitialOptions(creationParams)

        // TODO(MVP): 接入 Activity Lifecycle 分发 onResume/onPause
        mapView.onCreate(null)
        mapView.onResume()
        notifyDartMapCreated()
    }

    // ---- 初始配置（creationParams） ----

    private fun applyInitialOptions(params: Map<*, *>) {
        // 地图类型
        (params["mapType"] as? Number)?.let { typeCode ->
            amap.mapType = typeCode.toInt()
        }

        // 地图语言：0=中文 / 1=英文（英文仅标准地图生效，与自定义样式互斥）
        (params["language"] as? Number)?.let { langCode ->
            amap.setMapLanguage(if (langCode.toInt() == 1) AMap.ENGLISH else AMap.CHINESE)
        }

        // 缩放范围
        applyMinMaxZoom(params["minZoom"], params["maxZoom"])

        // 中心点可视范围限制
        // 仅在 Dart 显式下发非空 bounds 时才触碰限制属性：从未设置过就不要碰
        // （对齐 iOS 修复原则）；Dart 侧 creationParams 该键恒存在、未配置时为 null
        if (params["limitBounds"] != null) {
            applyLimitBounds(params["limitBounds"])
        }

        // 手势开关（US-04：缩放/平移/旋转/倾斜）
        applyGestures(params["gestures"])

        // UI 开关（路况/POI 点击/建筑物/标注/指南针/比例尺）
        applyUiOptions(params["uiOptions"])

        // 定位蓝点 + 样式
        amap.isMyLocationEnabled = (params["myLocationEnabled"] as? Boolean) ?: false
        (params["myLocationStyle"] as? Map<*, *>)?.let(::applyMyLocationStyle)

        // 自定义样式（官方样式 ID）
        (params["customStyle"] as? Map<*, *>)?.let(::applyCustomStyle)

        // 初始相机
        (params["initialCameraPosition"] as? Map<*, *>)?.let(::applyCameraPosition)

        // 覆盖物初始渲染
        applyOverlays(params)

        // 事件回调
        bindMapEvents()
    }

    private fun applyMinMaxZoom(min: Any?, max: Any?) {
        (min as? Number)?.let { amap.setMinZoomLevel(it.toFloat()) }
        (max as? Number)?.let { amap.setMaxZoomLevel(it.toFloat()) }
    }

    /// 应用中心点可视范围限制。bounds 缺失/解析失败视为"解除限制"，
    /// 用全世界矩形替代 setMapStatusLimits(null)（见 [WORLD_BOUNDS] 注释）。
    private fun applyLimitBounds(json: Any?) {
        val bounds = jsonToLatLngBounds(json)
        if (bounds != null) {
            amap.setMapStatusLimits(bounds)
        } else {
            amap.setMapStatusLimits(WORLD_BOUNDS)
        }
    }

    private fun applyUiOptions(json: Any?) {
        val options = json as? Map<*, *> ?: return
        (options["trafficEnabled"] as? Boolean)?.let { amap.setTrafficEnabled(it) }
        (options["touchPoiEnabled"] as? Boolean)?.let { amap.setTouchPoiEnable(it) }
        (options["buildingsEnabled"] as? Boolean)?.let { amap.showBuildings(it) }
        (options["labelsEnabled"] as? Boolean)?.let { amap.showMapText(it) }
        val ui = amap.uiSettings
        (options["compassEnabled"] as? Boolean)?.let { ui.isCompassEnabled = it }
        (options["scaleEnabled"] as? Boolean)?.let { ui.isScaleControlsEnabled = it }
        // 右下角 +/- 缩放按钮（iOS 无此 UI，该开关仅 Android 生效）
        (options["zoomControlsEnabled"] as? Boolean)?.let { ui.isZoomControlsEnabled = it }
    }

    private fun applyGestures(json: Any?) {
        val gestures = json as? Map<*, *> ?: return
        val ui = amap.uiSettings
        (gestures["zoom"] as? Boolean)?.let { ui.isZoomGesturesEnabled = it }
        (gestures["scroll"] as? Boolean)?.let { ui.isScrollGesturesEnabled = it }
        (gestures["rotate"] as? Boolean)?.let { ui.isRotateGesturesEnabled = it }
        (gestures["tilt"] as? Boolean)?.let { ui.isTiltGesturesEnabled = it }
    }

    private fun applyMyLocationStyle(json: Map<*, *>) {
        val style = MyLocationStyle()
        iconFromJson(json["icon"])?.let { style.myLocationIcon(it) }
        (json["circleFillColor"] as? Number)?.let {
            style.radiusFillColor(it.toInt())
        }
        (json["circleStrokeColor"] as? Number)?.let {
            style.strokeColor(it.toInt())
        }
        (json["circleStrokeWidth"] as? Number)?.let { style.strokeWidth(it.toFloat()) }
        // 按名称映射到原生常量，避免魔法数字漂移
        when (json["locationMode"] as? String) {
            "show" -> style.myLocationType(MyLocationStyle.LOCATION_TYPE_SHOW)
            "follow" -> style.myLocationType(MyLocationStyle.LOCATION_TYPE_FOLLOW)
            "mapRotate" -> style.myLocationType(MyLocationStyle.LOCATION_TYPE_MAP_ROTATE)
            "locationRotate" -> style.myLocationType(MyLocationStyle.LOCATION_TYPE_LOCATION_ROTATE)
            else -> style.myLocationType(MyLocationStyle.LOCATION_TYPE_LOCATE)
        }
        amap.myLocationStyle = style
    }

    private fun applyCustomStyle(json: Map<*, *>) {
        val enabled = (json["enabled"] as? Boolean) ?: true
        if (!enabled) return
        val options = CustomMapStyleOptions()
        // 本地样式数据优先（对齐官方），其次云端样式 ID（本插件扩展）
        val styleData = json["styleData"] as? ByteArray
        val styleExtraData = json["styleExtraData"] as? ByteArray
        if (styleData != null) {
            options.setStyleData(styleData)
        }
        if (styleExtraData != null) {
            options.setStyleExtraData(styleExtraData)
        }
        if (styleData == null && styleExtraData == null) {
            val styleId = json["customStyleId"] as? String
            if (!styleId.isNullOrBlank()) {
                options.setStyleId(styleId)
            }
        }
        amap.setCustomMapStyle(options.setEnable(true))
        // 11.x 起开关由 CustomMapStyleOptions.setEnable 控制（旧 AMap.setCustomMapStyleEnabled 已移除）
    }

    private fun applyCameraPosition(json: Map<*, *>) {
        val target = jsonToLatLng(json["target"]) ?: return
        val zoom = (json["zoom"] as? Number)?.toFloat() ?: 10f
        val tilt = (json["tilt"] as? Number)?.toFloat() ?: 0f
        val bearing = (json["bearing"] as? Number)?.toFloat() ?: 0f
        amap.moveCamera(
            CameraUpdateFactory.newCameraPosition(
                CameraPosition(target, zoom, tilt, bearing),
            ),
        )
    }

    private fun applyOverlays(params: Map<*, *>) {
        (params["markers"] as? List<*>)?.forEach { addMarker(it) }
        (params["polylines"] as? List<*>)?.forEach { addPolyline(it) }
        (params["polygons"] as? List<*>)?.forEach { addPolygon(it) }
        (params["circles"] as? List<*>)?.forEach { addCircle(it) }
    }

    // ---- 覆盖物构建 ----

    private fun addMarker(json: Any?) {
        val map = json as? Map<*, *> ?: return
        val id = map["id"] as? String ?: return
        val position = jsonToLatLng(map["position"]) ?: return
        if (markerById.containsKey(id)) return
        var showOnCreate = false

        val options = MarkerOptions()
            .position(position)
            .alpha((map["alpha"] as? Number)?.toFloat() ?: 1f)
            .rotateAngle((map["rotation"] as? Number)?.toFloat() ?: 0f)
            .draggable((map["draggable"] as? Boolean) ?: false)
            .setFlat((map["flat"] as? Boolean) ?: false)
            .visible((map["visible"] as? Boolean) ?: true)
            .zIndex((map["zIndex"] as? Number)?.toFloat() ?: 0f)
        (map["anchor"] as? List<*>)?.takeIf { it.size == 2 }?.let { anchor ->
            options.anchor(
                (anchor[0] as? Number)?.toFloat() ?: 0.5f,
                (anchor[1] as? Number)?.toFloat() ?: 1f,
            )
        }
        // infoWindowEnable=false 时禁用气泡：不设置 title/snippet，
        // SDK 气泡管线不生效，点击 Marker 永不弹出
        if ((map["infoWindowEnable"] as? Boolean) != false) {
            (map["infoWindow"] as? Map<*, *>)?.let { info ->
                (info["title"] as? String)?.let { options.title(it) }
                (info["snippet"] as? String)?.let { options.snippet(it) }
                // 自定义气泡内容（Widget 截图），非空时由 InfoWindowAdapter 接管显示。
                // SDK 约定（官方 InfoWindowAdapter 文档）：点击 marker 时只有
                // title 与 snippet 均非空才会触发 adapter 回调；showInfoWindow()
                // 编程式调用不受此限。因此两者都要兜底非空，否则点击 marker 会
                // 直接弹默认文字气泡 —— title 兜底空格时看起来就是"内容为空"。
                // 注意不要兜底 marker id —— adapter 一旦失效用户会看到 id 字样
                (info["content"] as? Map<*, *>)?.let { content ->
                    (content["bytes"] as? ByteArray)?.let { bytes ->
                        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                        if (bitmap == null) {
                            Log.e(TAG, "Failed to decode custom InfoWindow image for marker $id")
                        } else {
                            customCalloutById[id] = bitmap
                            if (info["title"] == null) options.title(INFO_WINDOW_PLACEHOLDER)
                            if (info["snippet"] == null) options.snippet(INFO_WINDOW_PLACEHOLDER)
                        }
                    }
                }
                showOnCreate = info["show"] == true
            }
        }
        iconFromJson(map["icon"])?.let { options.icon(it) }

        val marker = amap.addMarker(options)
        markerById[id] = marker
        markerIdByNativeId[marker.id] = id
        // 默认显示气泡（InfoWindow.show）
        if (showOnCreate) {
            marker.showInfoWindow()
            trackInfoWindowShown(id)
        }
    }

    private fun addPolyline(json: Any?) {
        val map = json as? Map<*, *> ?: return
        val id = map["id"] as? String ?: return
        val points = jsonToLatLngList(map["points"])
        if (points.size < 2 || polylineById.containsKey(id)) return

        val options = PolylineOptions()
            .addAll(points)
            .width((map["width"] as? Number)?.toFloat() ?: 10f)
            .color((map["color"] as? Number)?.toInt() ?: 0xCC0000FF.toInt())
            .visible((map["visible"] as? Boolean) ?: true)
            .zIndex((map["zIndex"] as? Number)?.toFloat() ?: 0f)
        when (map["capType"] as? String) {
            "round" -> options.lineCapType(PolylineOptions.LineCapType.LineCapRound)
            "square" -> options.lineCapType(PolylineOptions.LineCapType.LineCapSquare)
            "arrow" -> options.lineCapType(PolylineOptions.LineCapType.LineCapArrow)
            else -> options.lineCapType(PolylineOptions.LineCapType.LineCapButt)
        }
        when (map["joinType"] as? String) {
            "bevel" -> options.lineJoinType(PolylineOptions.LineJoinType.LineJoinBevel)
            "round" -> options.lineJoinType(PolylineOptions.LineJoinType.LineJoinRound)
            else -> options.lineJoinType(PolylineOptions.LineJoinType.LineJoinMiter)
        }
        // 高德虚线为布尔开关（点状线），dash/dashDot/dot 细分样式需自定义纹理（后续版本支持）
        options.setDottedLine(map["dashLineType"] as? String != "none")
        // 大地曲线（对齐官方 Polyline.geodesic）
        if ((map["geodesic"] as? Boolean) == true) {
            options.geodesic(true)
        }
        // 自定义纹理线（对齐官方 Polyline.customTexture）
        iconFromJson(map["customTexture"])?.let { options.setCustomTexture(it) }

        polylineById[id] = amap.addPolyline(options)
    }

    private fun addPolygon(json: Any?) {
        val map = json as? Map<*, *> ?: return
        val id = map["id"] as? String ?: return
        val points = jsonToLatLngList(map["points"])
        if (points.size < 3 || polygonById.containsKey(id)) return

        val options = PolygonOptions()
            .addAll(points)
            .strokeWidth((map["strokeWidth"] as? Number)?.toFloat() ?: 10f)
            .strokeColor((map["strokeColor"] as? Number)?.toInt() ?: 0xCC000000.toInt())
            .fillColor((map["fillColor"] as? Number)?.toInt() ?: 0)
            .visible((map["visible"] as? Boolean) ?: true)
            .zIndex((map["zIndex"] as? Number)?.toFloat() ?: 0f)

        // 孔洞环
        (map["holes"] as? List<*>)?.forEach { holeJson ->
            val hole = jsonToLatLngList(holeJson)
            if (hole.size >= 3) {
                options.addHoles(com.amap.api.maps.model.PolygonHoleOptions().addAll(hole))
            }
        }

        polygonById[id] = amap.addPolygon(options)
    }

    private fun addCircle(json: Any?) {
        val map = json as? Map<*, *> ?: return
        val id = map["id"] as? String ?: return
        val center = jsonToLatLng(map["center"]) ?: return
        if (circleById.containsKey(id)) return

        val options = CircleOptions()
            .center(center)
            .radius((map["radius"] as? Number)?.toDouble() ?: 0.0)
            .strokeWidth((map["strokeWidth"] as? Number)?.toFloat() ?: 10f)
            .strokeColor((map["strokeColor"] as? Number)?.toInt() ?: 0xCC000000.toInt())
            .fillColor((map["fillColor"] as? Number)?.toInt() ?: 0)
            .visible((map["visible"] as? Boolean) ?: true)
            .zIndex((map["zIndex"] as? Number)?.toFloat() ?: 0f)

        circleById[id] = amap.addCircle(options)
    }

    private fun removeMarker(id: String) {
        val removed = markerById.remove(id) ?: return
        markerIdByNativeId.remove(removed.id)
        removed.remove()
        customCalloutById.remove(id)
        if (shownInfoWindowMarkerId == id) shownInfoWindowMarkerId = null
    }

    /// Marker 差量更新：原地更新属性（不删不建）。
    ///
    /// 不要改成"删旧 + 建新"：本 SDK 版本对刚创建的 marker 首次弹窗时
    /// 不调用 InfoWindowAdapter，而是构建默认窗并固化（实测 10.1.200，
    /// 表现为点击只弹默认空泡，之后 hide/show 也不会再询问 adapter）。
    /// 原地更新保证 marker 自创建起持续"成熟"，气泡管线始终可用。
    private fun updateMarker(json: Any?) {
        val map = json as? Map<*, *> ?: return
        val id = map["id"] as? String ?: return
        val marker = markerById[id] ?: run { addMarker(json); return }
        val wasShown = marker.isInfoWindowShown
        if (wasShown) marker.hideInfoWindow()

        jsonToLatLng(map["position"])?.let { marker.position = it }
        (map["alpha"] as? Number)?.let { marker.setAlpha(it.toFloat()) }
        (map["rotation"] as? Number)?.let { marker.setRotateAngle(it.toFloat()) }
        (map["draggable"] as? Boolean)?.let { marker.setDraggable(it) }
        (map["flat"] as? Boolean)?.let { marker.setFlat(it) }
        (map["visible"] as? Boolean)?.let { marker.setVisible(it) }
        (map["zIndex"] as? Number)?.let { marker.setZIndex(it.toFloat()) }
        (map["anchor"] as? List<*>)?.takeIf { it.size == 2 }?.let { anchor ->
            marker.setAnchor(
                (anchor[0] as? Number)?.toFloat() ?: 0.5f,
                (anchor[1] as? Number)?.toFloat() ?: 1f,
            )
        }
        iconFromJson(map["icon"])?.let { marker.setIcon(it) }

        // infoWindow：title/snippet/content 原地同步。
        // infoWindowEnable=false → info=null，显式禁用；infoWindow 字段整体缺失
        // （info==null 且未禁用）→ 视为部分更新，气泡相关状态原样保留。
        val infoEnabled = (map["infoWindowEnable"] as? Boolean) != false
        val info = if (infoEnabled) map["infoWindow"] as? Map<*, *> else null
        var hasCustomCallout = false
        if (info != null) {
            (info["content"] as? Map<*, *>)?.let { content ->
                (content["bytes"] as? ByteArray)?.let { bytes ->
                    val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                    if (bitmap == null) {
                        Log.e(TAG, "Failed to decode custom InfoWindow image for marker $id")
                    } else {
                        customCalloutById[id] = bitmap
                        hasCustomCallout = true
                    }
                }
            }
            (info["title"] as? String)?.let { marker.setTitle(it) }
            (info["snippet"] as? String)?.let { marker.setSnippet(it) }
            if (hasCustomCallout) {
                // 占位符兜底，保证点击时 SDK 会调 InfoWindowAdapter（见常量注释）
                if (info["title"] == null) marker.setTitle(INFO_WINDOW_PLACEHOLDER)
                if (info["snippet"] == null) marker.setSnippet(INFO_WINDOW_PLACEHOLDER)
            } else {
                // 显式下发了 infoWindow（或禁用气泡）但无有效 content：清除旧气泡
                customCalloutById.remove(id)
            }
        }

        // show 字段语义：true → 显式弹出；false → 显式保持隐藏（更新前已打开的
        // 在上方 hideInfoWindow 关闭）；字段缺省 → 沿用更新前可见性。
        // 旧逻辑 `show==true || wasShown` 导致 show=false 无法关闭已打开的气泡。
        when (info?.get("show") as? Boolean) {
            true -> marker.showInfoWindow()
            false -> Unit
            null -> if (wasShown) marker.showInfoWindow()
        }
        // 同步 tap-to-dismiss 追踪（以 SDK 实际可见性为准，覆盖所有更新路径）
        if (marker.isInfoWindowShown) {
            trackInfoWindowShown(id)
        } else if (shownInfoWindowMarkerId == id) {
            shownInfoWindowMarkerId = null
        }
    }

    private fun removePolyline(id: String) {
        polylineById.remove(id)?.remove()
    }

    private fun removePolygon(id: String) {
        polygonById.remove(id)?.remove()
    }

    private fun removeCircle(id: String) {
        circleById.remove(id)?.remove()
    }

    // ---- 覆盖物差量更新通道 ----

    private fun applyOverlayUpdates(
        payload: Any?,
        add: (Any?) -> Unit,
        remove: (String) -> Unit,
        update: (Any?) -> Unit = { json ->
            idOf(json)?.let(remove)
            add(json)
        },
    ) {
        val map = payload as? Map<*, *> ?: return
        (map["toRemove"] as? List<*>)?.forEach { (it as? String)?.let(remove) }
        (map["toAdd"] as? List<*>)?.forEach(add)
        (map["toUpdate"] as? List<*>)?.forEach(update)
    }

    /// 从覆盖物 JSON payload 提取 Dart 侧 id，缺失时返回 null（调用方静默跳过）。
    private fun idOf(json: Any?): String? =
        (json as? Map<*, *>)?.get("id") as? String

    // ---- 事件绑定 ----

    private fun bindMapEvents() {
        amap.setOnMapClickListener { latLng ->
            // tap-to-dismiss：点击地图空白处关闭已显示的气泡，对齐 iOS 的
            // deselect 语义。iOS 上 deselect 与 mapTap 都会触发，这里同样
            // 关闭气泡后继续回发 mapTap。
            dismissTrackedInfoWindow()
            notifyDart("mapTap", latLng.toJsonList())
        }
        amap.setOnMapLongClickListener { latLng ->
            notifyDart("mapLongPress", latLng.toJsonList())
        }
        amap.addOnCameraChangeListener(object : AMap.OnCameraChangeListener {
            override fun onCameraChange(position: CameraPosition) {
                notifyDart("cameraMove", position.toJsonMap())
            }

            override fun onCameraChangeFinish(position: CameraPosition) {
                notifyDart("cameraMoveEnd", position.toJsonMap())
            }
        })
        amap.setOnMapLoadedListener {
            notifyDart("mapLoaded", null)
        }

        amap.setOnMarkerClickListener { marker ->
            val infoWindowWasShown = marker.isInfoWindowShown
            if (infoWindowWasShown) {
                marker.hideInfoWindow()
            } else {
                marker.showInfoWindow()
            }
            // 同步 tap-to-dismiss 追踪（再次点击同一 marker 为切换显隐）
            customMarkerId(marker)?.let { id ->
                if (infoWindowWasShown) {
                    if (shownInfoWindowMarkerId == id) shownInfoWindowMarkerId = null
                } else {
                    trackInfoWindowShown(id)
                }
            }
            customMarkerId(marker)?.let { notifyDart("markerTap", it) }
            true
        }
        amap.setOnInfoWindowClickListener { marker ->
            customMarkerId(marker)?.let { notifyDart("infoWindowTap", it) }
            true
        }
        // 自定义气泡：Dart 侧 Widget 截图替换整个气泡窗口。
        // ⚠️ SDK 约定（反编译 10.1.200 确认，ax.a/ax.b）：注册 adapter 时会用一个
        // 无 position 的探针 marker 调用 getInfoWindow/getInfoContents，若两者都
        // 返回 null，自定义 adapter 会被静默丢弃并替换为默认文字 adapter，之后
        // 永不生效。且 adapter 被采纳后（自定义模式），无 content 的 marker 也
        // 必须由本 adapter 渲染文字气泡 —— SDK 不再兜底，返回 null 即不弹窗。
        amap.setInfoWindowAdapter(object : AMap.InfoWindowAdapter {
            override fun getInfoWindow(marker: Marker): View? {
                // 探针（无 position）必须返回非 null，否则整个 adapter 被丢弃
                if (marker.position == null) return View(mapView.context)

                val id = customMarkerId(marker)
                val bitmap = id?.let { customCalloutById[it] }
                if (bitmap != null) {
                    return ImageView(mapView.context).apply {
                        // 显式布局参数：部分 SDK 版本对无 LayoutParams 的视图测量为 0 尺寸。
                        // ⚠️ 必须设置 background（哪怕全透明）：根 View 无背景时 SDK 会在
                        // 外面补一层默认白色 9-patch 气泡底框（社区反复踩坑确认），
                        // 设置后气泡 = Widget 截图本身，无白框。
                        setBackgroundColor(0x00000000)
                        layoutParams = ViewGroup.LayoutParams(
                            ViewGroup.LayoutParams.WRAP_CONTENT,
                            ViewGroup.LayoutParams.WRAP_CONTENT,
                        )
                        setImageBitmap(bitmap)
                    }
                }

                // 无 content：自行渲染默认样式文字气泡（title 加粗黑 / snippet 灰）
                val title = marker.title
                val snippet = marker.snippet
                if (title.isNullOrEmpty() && snippet.isNullOrEmpty()) return null
                val density = mapView.context.resources.displayMetrics.density
                return LinearLayout(mapView.context).apply {
                    orientation = LinearLayout.VERTICAL
                    val padH = (12 * density).toInt()
                    val padV = (6 * density).toInt()
                    setPadding(padH, padV, padH, padV)
                    if (!title.isNullOrEmpty()) {
                        addView(
                            TextView(mapView.context).apply {
                                text = title
                                setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
                                setTextColor(0xFF000000.toInt())
                                paint.isFakeBoldText = true
                            },
                        )
                    }
                    if (!snippet.isNullOrEmpty()) {
                        addView(
                            TextView(mapView.context).apply {
                                text = snippet
                                setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                                setTextColor(0xFF666666.toInt())
                            },
                        )
                    }
                }
            }

            override fun getInfoContents(marker: Marker): View? = null
        })
        amap.setOnMarkerDragListener(object : AMap.OnMarkerDragListener {
            override fun onMarkerDragStart(marker: Marker) {}

            override fun onMarkerDrag(marker: Marker) {}

            override fun onMarkerDragEnd(marker: Marker) {
                val id = customMarkerId(marker) ?: return
                notifyDart(
                    "markerDragEnd",
                    mapOf("id" to id, "position" to marker.position.toJsonList()),
                )
            }
        })
        amap.setOnPOIClickListener { poi ->
            notifyDart(
                "poiTap",
                mapOf(
                    "id" to (poi.poiId ?: ""),
                    "name" to poi.name,
                    "position" to poi.coordinate.toJsonList(),
                ),
            )
        }
    }

    private fun customMarkerId(native: Marker): String? = markerIdByNativeId[native.id]

    /// 记录气泡已显示。所有 showInfoWindow 调用点统一走此入口，
    /// 保证 tap-to-dismiss 追踪状态与实际显隐一致。
    private fun trackInfoWindowShown(id: String) {
        shownInfoWindowMarkerId = id
    }

    /// 关闭当前追踪的气泡（若存在）。返回是否真的关闭了一个。
    private fun dismissTrackedInfoWindow(): Boolean {
        val id = shownInfoWindowMarkerId ?: return false
        shownInfoWindowMarkerId = null
        markerById[id]?.hideInfoWindow()
        return true
    }

    // ---- 相机更新 ----

    /// 统一入口：zoomByFocus 需要当前相机/投影信息，单独处理；
    /// 其余 op 走纯 payload 映射。
    private fun cameraUpdateOrFocus(payload: Any?): CameraUpdate? {
        val json = payload as? Map<*, *> ?: return null
        if (json["op"] == "zoomByFocus") return zoomByFocusUpdate(json)
        return cameraUpdateFromPayload(payload)
    }

    /// 以屏幕坐标 (focusX, focusY) 为不动点缩放 [amount] 级。
    ///
    /// 高德 SDK 无带焦点的 zoomBy 工厂，用投影换算模拟：
    /// 缩放后新中心 = fromScreenLocation(F + (C_screen - F) * 2^-amount)，
    /// 使焦点的地理坐标保持在原屏幕位置。
    private fun zoomByFocusUpdate(json: Map<*, *>): CameraUpdate? {
        val amount = (json["amount"] as? Number)?.toFloat() ?: return null
        val focus = json["focus"] as? List<*> ?: return null
        val focusX = (focus.getOrNull(0) as? Number)?.toFloat() ?: return null
        val focusY = (focus.getOrNull(1) as? Number)?.toFloat() ?: return null
        val pos = amap.cameraPosition ?: return null
        val w = mapView.width
        val h = mapView.height
        if (w <= 0 || h <= 0) return null
        // focus 为 Flutter 逻辑像素（dp），Android 屏幕坐标为物理像素，
        // 先乘 density 对齐单位（iOS point 与逻辑像素天然一致，无需换算）
        val density = mapView.resources.displayMetrics.density
        val focusPx = focusX * density
        val focusPy = focusY * density
        // 先按 min/max 钳制出目标 zoom，再用有效缩放量换算焦点：
        // 若直接用请求的 amount 换算，相机已在 min/max 时焦点会漂移
        val newZoom = (pos.zoom + amount).coerceIn(amap.minZoomLevel, amap.maxZoomLevel)
        val effectiveAmount = newZoom - pos.zoom
        val factor = Math.pow(2.0, -effectiveAmount.toDouble())
        val newScreenX = (focusPx + (w / 2.0 - focusPx) * factor).toInt()
        val newScreenY = (focusPy + (h / 2.0 - focusPy) * factor).toInt()
        val newTarget = amap.projection.fromScreenLocation(Point(newScreenX, newScreenY))
        return CameraUpdateFactory.newLatLngZoom(newTarget, newZoom)
    }

    /// 截图监听统一封装：不同 SDK 版本可能只回调单参或双参重载之一（部分版本
    /// 只走 `onMapScreenShot(bitmap, status)`），若只在单参里应答会导致 result
    /// 永不返回、Dart 侧 Future 悬挂。两个重载都参与去重，保证 [onShot] 恰好
    /// 执行一次；SDK 失败时可能回调 null 位图（平台类型），由调用方兜底。
    private fun takeMapScreenShot(onShot: (Bitmap?) -> Unit) {
        amap.getMapScreenShot(object : AMap.OnMapScreenShotListener {
            private var answered = false

            private fun answer(bitmap: Bitmap?) {
                if (answered) return
                answered = true
                onShot(bitmap)
            }

            override fun onMapScreenShot(bitmap: Bitmap) {
                answer(bitmap)
            }

            override fun onMapScreenShot(bitmap: Bitmap, status: Int) {
                answer(bitmap)
            }
        })
    }

    // ---- MethodChannel 处理 ----

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "map#moveCamera" -> {
                // 兼容两种 payload：纯 update（旧版）/ {update, animated, durationMs}
                val args = call.arguments as? Map<*, *>
                val update = cameraUpdateOrFocus(args?.get("update") ?: call.arguments)
                if (update == null) {
                    result.error("BAD_ARGS", "invalid camera update: ${call.arguments}", null)
                } else {
                    val animated = (args?.get("animated") as? Boolean) ?: false
                    if (animated) {
                        val durationMs = (args?.get("durationMs") as? Number)?.toLong() ?: 250L
                        amap.animateCamera(update, durationMs, null)
                    } else {
                        amap.moveCamera(update)
                    }
                    result.success(null)
                }
            }
            "map#animateCamera" -> {
                val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                val update = cameraUpdateOrFocus(args["update"])
                if (update == null) {
                    result.error("BAD_ARGS", "invalid camera update: ${args["update"]}", null)
                } else {
                    amap.animateCamera(update)
                    result.success(null)
                }
            }
            "map#getCameraPosition" -> {
                val pos = amap.cameraPosition ?: run {
                    result.success(null)
                    return
                }
                result.success(pos.toJsonMap())
            }
            "map#getVisibleRegion" -> {
                val bounds = amap.projection.visibleRegion.latLngBounds
                result.success(bounds.toJsonList())
            }
            "map#getContentApprovalNumber" -> {
                result.success(amap.mapContentApprovalNumber)
            }
            "map#getSatelliteApprovalNumber" -> {
                result.success(amap.satelliteImageApprovalNumber)
            }
            "map#setMapType" -> {
                (call.arguments as? Number)?.let { amap.mapType = it.toInt() }
                result.success(null)
            }
            "map#setLanguage" -> {
                val langCode = (call.arguments as? Number)?.toInt() ?: 0
                amap.setMapLanguage(if (langCode == 1) AMap.ENGLISH else AMap.CHINESE)
                result.success(null)
            }
            "map#dispose" -> {
                // Dart State.dispose 驱动的释放（幂等兜底）：Android 引擎本就会
                // 自动调 dispose()，此消息仅在引擎路径迟到/未触发时兜底
                dispose()
                result.success(null)
            }
            "map#setCustomStyle" -> {
                // 动态切换自定义样式（无需重建地图）；
                // null 或 enabled=false 关闭自定义样式
                val style = call.arguments as? Map<*, *>
                if (style != null && (style["enabled"] as? Boolean) ?: true) {
                    applyCustomStyle(style)
                } else {
                    // 11.x：通过空的关闭态 Options 关闭自定义样式（替代 setCustomMapStyleEnabled(false)）
                    amap.setCustomMapStyle(CustomMapStyleOptions().setEnable(false))
                }
                result.success(null)
            }
            "map#setMinMaxZoomPreference" -> {
                val json = call.arguments as? Map<*, *>
                applyMinMaxZoom(json?.get("min"), json?.get("max"))
                result.success(null)
            }
            "map#setLimitBounds" -> {
                applyLimitBounds(call.arguments)
                result.success(null)
            }
            "map#setUiOptions" -> {
                applyUiOptions(call.arguments)
                result.success(null)
            }
            "map#setGestures" -> {
                applyGestures(call.arguments)
                result.success(null)
            }
            "map#updateMarkers" -> {
                applyOverlayUpdates(call.arguments, ::addMarker, ::removeMarker, ::updateMarker)
                result.success(null)
            }
            "map#updatePolylines" -> {
                applyOverlayUpdates(call.arguments, ::addPolyline, ::removePolyline)
                result.success(null)
            }
            "map#updatePolygons" -> {
                applyOverlayUpdates(call.arguments, ::addPolygon, ::removePolygon)
                result.success(null)
            }
            "map#updateCircles" -> {
                applyOverlayUpdates(call.arguments, ::addCircle, ::removeCircle)
                result.success(null)
            }
            "map#showInfoWindow" -> {
                (call.arguments as? String)?.let { id ->
                    markerById[id]?.showInfoWindow()
                    trackInfoWindowShown(id)
                }
                result.success(null)
            }
            "map#hideInfoWindow" -> {
                (call.arguments as? String)?.let { id ->
                    markerById[id]?.hideInfoWindow()
                    if (shownInfoWindowMarkerId == id) shownInfoWindowMarkerId = null
                }
                result.success(null)
            }
            "map#takeSnapshot" -> {
                takeMapScreenShot { bitmap ->
                    if (bitmap == null) {
                        result.error("SNAPSHOT_FAILED", "AMap returned null screenshot bitmap", null)
                    } else {
                        val stream = ByteArrayOutputStream()
                        bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
                        result.success(stream.toByteArray())
                    }
                }
            }
            "map#freeze" -> {
                freezeMap()
                result.success(null)
            }
            "map#unfreeze" -> {
                unfreezeMap()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun cameraUpdateFromPayload(payload: Any?): CameraUpdate? {
        val json = payload as? Map<*, *> ?: return null
        return when (json["op"] as? String) {
            "newLatLng" -> jsonToLatLng(json["latLng"])?.let(CameraUpdateFactory::newLatLng)
            "newLatLngZoom" -> {
                val target = jsonToLatLng(json["latLng"]) ?: return null
                val zoom = (json["zoom"] as? Number)?.toFloat() ?: return null
                CameraUpdateFactory.newLatLngZoom(target, zoom)
            }
            "newLatLngBounds" -> {
                val bounds = jsonToLatLngBounds(json["bounds"]) ?: return null
                val padding = (json["padding"] as? Number)?.toInt() ?: 0
                CameraUpdateFactory.newLatLngBounds(bounds, padding)
            }
            "newCameraPosition" -> {
                val pos = json["cameraPosition"] as? Map<*, *> ?: return null
                val target = jsonToLatLng(pos["target"]) ?: return null
                CameraUpdateFactory.newCameraPosition(
                    CameraPosition(
                        target,
                        (pos["zoom"] as? Number)?.toFloat() ?: 10f,
                        (pos["tilt"] as? Number)?.toFloat() ?: 0f,
                        (pos["bearing"] as? Number)?.toFloat() ?: 0f,
                    ),
                )
            }
            "zoomTo" -> {
                val zoom = (json["zoom"] as? Number)?.toFloat() ?: return null
                CameraUpdateFactory.zoomTo(zoom)
            }
            "zoomIn" -> CameraUpdateFactory.zoomIn()
            "zoomOut" -> CameraUpdateFactory.zoomOut()
            "zoomBy" -> {
                val amount = (json["amount"] as? Number)?.toFloat() ?: return null
                CameraUpdateFactory.zoomBy(amount)
            }
            "scrollBy" -> {
                val dx = (json["dx"] as? Number)?.toFloat() ?: 0f
                val dy = (json["dy"] as? Number)?.toFloat() ?: 0f
                // Dart 约定逻辑像素：乘 density 转物理像素（iOS point 与逻辑
                // 像素天然等值；对齐 google_maps_flutter 官方插件的换算惯例）
                val density = mapView.resources.displayMetrics.density
                CameraUpdateFactory.scrollBy(dx * density, dy * density)
            }
            else -> null
        }
    }

    // ---- 生命周期 ----

    override fun getView() = container

    /// 冻结：截图接管显示 + 立即隐藏 GLSurfaceView。
    ///
    /// GL 层的 surface/EGL 销毁是 GL 线程异步的，若等到 dispose（pop 动画结束
    /// 之后）才处理，最后一帧地图会叠在已返回的上一页上 1~2 帧（"一闪而过"）。
    /// 冻结必须在 pop 转场开始时调用：此时 GL 层销毁的视觉差被截图无缝覆盖。
    private fun freezeMap() {
        if (frozen || disposed) return
        takeMapScreenShot { bitmap ->
            // 位图缺失（SDK 失败）或已销毁：放弃冻结，保持活地图原样
            if (disposed || bitmap == null) return@takeMapScreenShot
            frozen = true
            freezeView.setImageBitmap(bitmap)
            freezeView.visibility = View.VISIBLE
            // GLSurfaceView 退场：surface 异步销毁期间，冻结截图与残帧内容
            // 一致（同屏内容），视觉无感；转场结束时 GL 层早已销毁干净。
            mapView.visibility = View.GONE
        }
    }

    /// 解冻：转场被取消（如预测性返回滑回）时恢复活地图。
    private fun unfreezeMap() {
        if (!frozen || disposed) return
        frozen = false
        freezeView.visibility = View.GONE
        mapView.visibility = View.VISIBLE
    }

    override fun dispose() {
        if (disposed) return
        disposed = true
        channel.setMethodCallHandler(null)
        AmapMapsFlutterQsPlugin.unregisterView(mapId)
        markerById.clear()
        markerIdByNativeId.clear()
        customCalloutById.clear()
        shownInfoWindowMarkerId = null
        polylineById.clear()
        polygonById.clear()
        circleById.clear()
        // GLSurfaceView 的 surface/EGL 销毁是异步的（GL 线程）：onPause 后最后一帧
        // 地图仍占据合成层，直到 surfaceDestroyed 真正完成（日志可见 surface lost →
        // releasing EGL context 的时序差）。若不先立即隐藏，返回上一页后残留帧会
        // 叠现 1~2 帧，表现为"地图一闪而过"。先 GONE 让视图当场退出可见层级。
        mapView.visibility = View.GONE
        mapView.onPause()
        mapView.onDestroy()
    }

    // ---- Dart 通知 ----

    private fun notifyDartMapCreated() {
        notifyDart("mapCreated", mapId)
    }

    private fun notifyDart(method: String, arguments: Any?) {
        try {
            channel.invokeMethod(method, arguments)
        } catch (e: Exception) {
            Log.w(TAG, "invokeMethod $method failed: ${e.message}")
        }
    }

    // ---- JSON 转换辅助 ----

    private fun jsonToLatLng(json: Any?): LatLng? {
        if (json !is List<*> || json.size < 2) return null
        return LatLng(
            (json[0] as? Number)?.toDouble() ?: return null,
            (json[1] as? Number)?.toDouble() ?: return null,
        )
    }

    private fun jsonToLatLngList(json: Any?): List<LatLng> {
        if (json !is List<*>) return emptyList()
        return json.mapNotNull(::jsonToLatLng)
    }

    private fun jsonToLatLngBounds(json: Any?): LatLngBounds? {
        if (json !is List<*> || json.size < 2) return null
        val sw = jsonToLatLng(json[0]) ?: return null
        val ne = jsonToLatLng(json[1]) ?: return null
        return LatLngBounds(sw, ne)
    }

    private fun iconFromJson(json: Any?): com.amap.api.maps.model.BitmapDescriptor? {
        val map = json as? Map<*, *> ?: return null
        return when (map["type"] as? String) {
            // SDK 默认图标（可带色相着色）
            "defaultMarker" ->
                iconCache.get("default") ?: BitmapDescriptorFactory.defaultMarker()?.also {
                    iconCache.put("default", it)
                }
            "defaultMarkerWithHue" ->
                (map["hue"] as? Number)?.let { hue ->
                    val key = "hue:$hue"
                    iconCache.get(key) ?: BitmapDescriptorFactory.defaultMarker(hue.toFloat())?.also {
                        iconCache.put(key, it)
                    }
                }
            // Flutter 资源（fromIconPath / fromAssetImage），见 assetIcon()
            "asset", "assetImage" -> (map["asset"] as? String)?.let { path ->
                assetIcon(
                    path,
                    (map["width"] as? Number)?.toDouble(),
                    (map["height"] as? Number)?.toDouble(),
                )
            }
            "bytes" -> (map["bytes"] as? ByteArray)?.let { bytes ->
                val widthDp = (map["width"] as? Number)?.toDouble()
                val heightDp = (map["height"] as? Number)?.toDouble()
                val key = "${bytes.cacheKey()}:${widthDp ?: 0.0}:${heightDp ?: 0.0}"
                val cached = iconCache.get(key)
                if (cached != null) {
                    cached
                } else {
                    val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                    val descriptor = bitmap?.let {
                        BitmapDescriptorFactory.fromBitmap(scaledByDp(it, widthDp, heightDp))
                    }
                    if (descriptor != null) {
                        iconCache.put(key, descriptor)
                    } else {
                        Log.e(TAG, "Failed to decode icon bytes (${bytes.size} bytes)")
                    }
                    descriptor
                }
            }
            else -> null
        }
    }

    /// Flutter 资源图标 → BitmapDescriptor。
    ///
    /// Flutter 资源打包在 APK 的 `flutter_assets/` 目录下，不能把 Dart 侧
    /// 的 asset 路径直接交给高德 `BitmapDescriptorFactory.fromAsset`（它按
    /// APK 根路径打开，必然失败返回 null；旧实现把返回的 null 缓存进
    /// LruCache，触发 `key == null || value == null` 崩溃）。
    /// 这里用 Flutter embedding 的 `getLookupKeyForAsset` 解析出真实路径
    /// （如 `flutter_assets/assets/texture_green.png`），自行解码后走
    /// `fromBitmap`。分辨率变体（"2.0x/" 前缀）优先按原始路径查找，
    /// 失败再回退去掉变体目录的基础路径。
    ///
    /// 任何失败只记日志并返回 null，绝不缓存 null —— 调用方对 null 已有
    /// 兜底（Marker 回退默认图标 / Polyline 回退纯色）。
    private fun assetIcon(
        path: String,
        widthDp: Double? = null,
        heightDp: Double? = null,
    ): BitmapDescriptor? {
        val cacheKey = "asset:$path:${widthDp ?: 0.0}:${heightDp ?: 0.0}"
        iconCache.get(cacheKey)?.let { return it }
        val stripped = path.replace(Regex("""^\d+(\.\d+)?x/"""), "")
        val candidates = if (stripped == path) listOf(path) else listOf(path, stripped)
        for (candidate in candidates) {
            val lookupKey = FlutterInjector.instance()
                .flutterLoader()
                .getLookupKeyForAsset(candidate)
            val bitmap = try {
                appContext.assets.open(lookupKey).use { input ->
                    BitmapFactory.decodeStream(input)
                }
            } catch (e: Exception) {
                null
            } ?: continue
            return BitmapDescriptorFactory.fromBitmap(scaledByDp(bitmap, widthDp, heightDp))?.also {
                iconCache.put(cacheKey, it)
            }
        }
        Log.e(TAG, "Failed to load Flutter asset icon: $path")
        return null
    }

    /// 按目标逻辑点尺寸缩放位图（fromIconPath / fromBytes 的 width/height）。
    ///
    /// [widthDp] / [heightDp] 只给其一时，另一边按原图宽高比推导；
    /// 都为 null 时原样返回。缩放结果随尺寸一起参与缓存键，
    /// 避免同路径不同尺寸互相污染。
    private fun scaledByDp(bitmap: Bitmap, widthDp: Double?, heightDp: Double?): Bitmap {
        if (widthDp == null && heightDp == null) return bitmap
        val density = appContext.resources.displayMetrics.density
        val targetW =
            if (widthDp != null) (widthDp * density).toInt().coerceAtLeast(1)
            else (heightDp!! * density * bitmap.width.toDouble() / bitmap.height)
                .toInt().coerceAtLeast(1)
        val targetH =
            if (heightDp != null) (heightDp * density).toInt().coerceAtLeast(1)
            else (widthDp!! * density * bitmap.height.toDouble() / bitmap.width)
                .toInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(bitmap, targetW, targetH, true)
    }

    private fun LatLng.toJsonList() = listOf(latitude, longitude)

    private fun LatLngBounds.toJsonList() = listOf(southwest.toJsonList(), northeast.toJsonList())

    private fun CameraPosition.toJsonMap(): Map<String, Any?> = mapOf(
        "target" to target.toJsonList(),
        "zoom" to zoom.toDouble(),
        "tilt" to tilt.toDouble(),
        "bearing" to bearing.toDouble(),
    )
}
