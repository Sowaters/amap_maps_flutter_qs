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
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import com.amap.api.maps.AMap
import com.amap.api.maps.CameraUpdate
import com.amap.api.maps.CameraUpdateFactory
import com.amap.api.maps.MapView
import com.amap.api.maps.model.BitmapDescriptorFactory
import com.amap.api.maps.model.CameraPosition
import com.amap.api.maps.model.Circle
import com.amap.api.maps.model.CircleOptions
import com.amap.api.maps.model.LatLng
import com.amap.api.maps.model.LatLngBounds
import com.amap.api.maps.model.Marker
import com.amap.api.maps.model.MarkerOptions
import com.amap.api.maps.model.Polygon
import com.amap.api.maps.model.PolygonOptions
import com.amap.api.maps.model.Polyline
import com.amap.api.maps.model.PolylineOptions
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import java.io.ByteArrayOutputStream

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
    }

    private val mapId: Int = (creationParams["mapId"] as? Number)?.toInt() ?: -1
    private val mapView = MapView(context)
    private val amap: AMap = mapView.map
    private val channel = MethodChannel(
        binaryMessenger,
        "${AmapMapsFlutterQsPlugin.MAIN_CHANNEL}/map#$mapId",
    )
    private var disposed = false

    // ---- 覆盖物注册表：Dart 侧 id -> 原生对象 ----
    private val markerById = LinkedHashMap<String, Marker>()
    private val polylineById = LinkedHashMap<String, Polyline>()
    private val polygonById = LinkedHashMap<String, Polygon>()
    private val circleById = LinkedHashMap<String, Circle>()

    // 自定义气泡内容：Dart 侧 id -> 气泡图片
    private val customCalloutById = HashMap<String, Bitmap>()

    /// 图标描述缓存：key -> 已构建的 BitmapDescriptor。
    ///
    /// 大量 Marker（几百~几千）共用同一图标时，无缓存意味着每个 marker
    /// 每次新增/更新都要 decodeByteArray + fromBitmap（bytes 类型），既慢
    /// 又重复产生位图内存。按 key 缓存后同图标只构建一次。
    /// 上限 64 条：单地图图标种类远小于 marker 数量，LRU 防极端场景膨胀。
    private val iconCache = object : LruCache<String, com.amap.api.maps.model.BitmapDescriptor>(64) {}

    /// bytes 图标的缓存 key：内容 MD5 摘要（128 位，非加密用途，足够防碰撞）。
    private fun ByteArray.cacheKey(): String {
        val digest = java.security.MessageDigest.getInstance("MD5").digest(this)
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

        // 缩放范围
        applyMinMaxZoom(params["minZoom"], params["maxZoom"])

        // 中心点可视范围限制
        applyLimitBounds(params["limitBounds"])

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

    private fun applyLimitBounds(json: Any?) {
        val bounds = jsonToLatLngBounds(json)
        if (bounds == null) {
            amap.setMapStatusLimits(null)
        } else {
            amap.setMapStatusLimits(bounds)
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
        val style = com.amap.api.maps.model.MyLocationStyle()
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
            "show" -> style.myLocationType(com.amap.api.maps.model.MyLocationStyle.LOCATION_TYPE_SHOW)
            "follow" -> style.myLocationType(com.amap.api.maps.model.MyLocationStyle.LOCATION_TYPE_FOLLOW)
            "mapRotate" -> style.myLocationType(com.amap.api.maps.model.MyLocationStyle.LOCATION_TYPE_MAP_ROTATE)
            "locationRotate" -> style.myLocationType(com.amap.api.maps.model.MyLocationStyle.LOCATION_TYPE_LOCATION_ROTATE)
            else -> style.myLocationType(com.amap.api.maps.model.MyLocationStyle.LOCATION_TYPE_LOCATE)
        }
        amap.myLocationStyle = style
    }

    private fun applyCustomStyle(json: Map<*, *>) {
        val enabled = (json["enabled"] as? Boolean) ?: true
        if (!enabled) return
        val options = com.amap.api.maps.model.CustomMapStyleOptions()
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
        amap.setCustomMapStyle(options)
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
        // 默认显示气泡（InfoWindow.show）
        if (showOnCreate) marker.showInfoWindow()
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
        markerById.remove(id)?.remove()
        customCalloutById.remove(id)
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

        // infoWindow：title/snippet/content 原地同步
        val enabled = (map["infoWindowEnable"] as? Boolean) != false
        val info = if (enabled) map["infoWindow"] as? Map<*, *> else null
        var hasCustomCallout = false
        if (info != null) {
            (info["content"] as? Map<*, *>)?.let { content ->
                (content["bytes"] as? ByteArray)?.let { bytes ->
                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.let { bitmap ->
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
            }
        }
        if (!hasCustomCallout) customCalloutById.remove(id)
        if (info?.get("show") == true || wasShown) marker.showInfoWindow()
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
            ((json as? Map<*, *>)?.get("id") as? String)?.let(remove)
            add(json)
        },
    ) {
        val map = payload as? Map<*, *> ?: return
        (map["toRemove"] as? List<*>)?.forEach { (it as? String)?.let(remove) }
        (map["toAdd"] as? List<*>)?.forEach(add)
        (map["toUpdate"] as? List<*>)?.forEach(update)
    }

    // ---- 事件绑定 ----

    private fun bindMapEvents() {
        amap.setOnMapClickListener { latLng ->
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
            Log.d(
                TAG,
                "onMarkerClick id=${customMarkerId(marker)} shown=$infoWindowWasShown " +
                    "title=${marker.title} snippet=${marker.snippet} " +
                    "callout=${customCalloutById[customMarkerId(marker)]?.let { "${it.width}x${it.height}" }}",
            )
            if (infoWindowWasShown) {
                marker.hideInfoWindow()
            } else {
                marker.showInfoWindow()
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
                    Log.d(TAG, "Rendering custom InfoWindow marker=$id bitmap=${bitmap.width}x${bitmap.height}")
                    return ImageView(mapView.context).apply {
                        // 显式布局参数：部分 SDK 版本对无 LayoutParams 的视图测量为 0 尺寸；
                        // 背景留空，SDK 会补默认 9-patch 气泡底框
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

    private fun customMarkerId(native: Marker): String? =
        markerById.entries.firstOrNull { it.value.id == native.id }?.key

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
        val factor = Math.pow(2.0, -amount.toDouble())
        val newScreenX = (focusX + (w / 2.0 - focusX) * factor).toInt()
        val newScreenY = (focusY + (h / 2.0 - focusY) * factor).toInt()
        val newTarget = amap.projection.fromScreenLocation(Point(newScreenX, newScreenY))
        val newZoom = (pos.zoom + amount).coerceIn(amap.minZoomLevel, amap.maxZoomLevel)
        return CameraUpdateFactory.newLatLngZoom(newTarget, newZoom)
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
                (call.arguments as? String)?.let { markerById[it]?.showInfoWindow() }
                result.success(null)
            }
            "map#hideInfoWindow" -> {
                (call.arguments as? String)?.let { markerById[it]?.hideInfoWindow() }
                result.success(null)
            }
            "map#takeSnapshot" -> {
                amap.getMapScreenShot(object : AMap.OnMapScreenShotListener {
                    private var answered = false

                    override fun onMapScreenShot(bitmap: Bitmap) {
                        if (answered) return
                        answered = true
                        val stream = ByteArrayOutputStream()
                        bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
                        result.success(stream.toByteArray())
                    }

                    override fun onMapScreenShot(bitmap: Bitmap, status: Int) {
                        // 二次回调忽略，避免 result 重复应答
                    }
                })
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
                CameraUpdateFactory.scrollBy(dx, dy)
            }
            else -> null
        }
    }

    // ---- 生命周期 ----

    override fun getView() = mapView

    override fun dispose() {
        if (disposed) return
        disposed = true
        channel.setMethodCallHandler(null)
        AmapMapsFlutterQsPlugin.unregisterView(mapId)
        markerById.clear()
        customCalloutById.clear()
        polylineById.clear()
        polygonById.clear()
        circleById.clear()
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
                iconCache.get("default") ?: BitmapDescriptorFactory.defaultMarker().also {
                    iconCache.put("default", it)
                }
            "defaultMarkerWithHue" ->
                (map["hue"] as? Number)?.let { hue ->
                    val key = "hue:$hue"
                    iconCache.get(key) ?: BitmapDescriptorFactory.defaultMarker(hue.toFloat()).also {
                        iconCache.put(key, it)
                    }
                }
            // asset 路径；assetImage 类型去除分辨率目录前缀（如 "2.0x/"）
            "asset", "assetImage" -> (map["asset"] as? String)?.let { path ->
                val name = path.replace(Regex("""^\d+(\.\d+)?x/"""), "")
                val key = "asset:$name"
                iconCache.get(key) ?: BitmapDescriptorFactory.fromAsset(name).also {
                    iconCache.put(key, it)
                }
            }
            "bytes" -> (map["bytes"] as? ByteArray)?.let { bytes ->
                val key = bytes.cacheKey()
                iconCache.get(key) ?: BitmapFactory
                    .decodeByteArray(bytes, 0, bytes.size)
                    ?.let { BitmapDescriptorFactory.fromBitmap(it) }
                    ?.also { iconCache.put(key, it) }
            }
            else -> null
        }
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
