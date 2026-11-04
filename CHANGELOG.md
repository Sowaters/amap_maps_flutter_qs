## 0.0.1

- **Android 气泡 tap-to-dismiss（对齐 iOS）**：Android SDK 的 InfoWindow 不会因点击地图空白处自动关闭（iOS 是原生 deselect 行为），现由插件追踪当前显示气泡的 marker（`shownInfoWindowMarkerId`），地图空白点击时主动关闭；marker 点击切换显隐、`showInfoWindow`/`hideInfoWindow`、更新路径（以 `isInfoWindowShown` 为准）与删除等所有显隐入口统一同步追踪状态。mapTap 仍照常回发（与 iOS deselect + mapTap 双事件语义一致）
- **iOS 代码审查整改（对齐 Android 整改轮）**：
  - `viewFor` 复用池视图无条件重置视觉属性：`customCalloutView` / rotation transform / alpha / zIndex（旧实现字段缺省时残留上一轮 marker 的值，复用后可能弹出别的 marker 的 Widget 截图气泡）
  - `removeMarker` / `hideInfoWindow` 补清 `programmaticSelection`（残留条目会吞掉同 id marker 的下一次真实点击）
  - `newLatLngBounds` 加退化矩形守卫（零尺寸 rect 与 limitMapRect 零矩形蓝屏同源风险）
  - `takeSnapshot` 保证 result 恰好应答一次（地图 dispose 后回调到达不再悬挂 Dart Future）
  - `mapLoaded` 后初始相机重设加跳过守卫：用户已在加载前手势移动相机（lastGoodCamera 距初始目标超一个视口宽）时不再拉回初始位置
  - `zoomByFocus` 实现焦点投影换算（此前降级为普通 zoomBy，两端行为分叉）；`scrollBy` 修正单位语义：Dart 逻辑像素与 iOS point 等值直接平移（旧实现除以 scale，3x 设备实际滚动距离只有请求量的 1/3）
  - `UIScreen.main` 弃用 API 全部替换（traitCollection/window.screen 兜底链）；cameraMove 去重改分量比较（消除手势期间每帧字典字符串插值）；`var status` → `let`、poiTap 字段显式兜底，swiftc typecheck 0 warning
- **Android 相机单位语义修正**：`scrollBy` 与 `zoomByFocus` 的 focus/dx/dy 均为 Flutter 逻辑像素，Android 端乘 density 转物理像素（对齐 google_maps_flutter 官方惯例；iOS point 与逻辑像素天然等值无需换算）。旧实现 3x 设备上滚动/焦点换算距离只有请求量的约 1/3
- **Android 代码健壮性整改（代码审查落地）**：
  - `applyLimitBounds` 空值语义对齐 iOS 修复原则：建图时未显式下发 bounds 不再触碰 `setMapStatusLimits`，显式解除改用全世界矩形（不再传 null，规避 iOS 蓝屏同源风险）
  - `takeSnapshot` / `freezeMap` 截图监听统一为单发助手：单参/双参重载都参与去重应答（部分 SDK 版本只回调双参，旧实现会导致 Dart 侧 Future 永久悬挂），并兜底 null 位图（返回 `SNAPSHOT_FAILED` 错误而非 NPE）
  - `updateMarker` 修复三处：`show=false` 现在能关闭已打开的气泡（旧逻辑 `show||wasShown` 会重新弹出）；payload 缺 `infoWindow` 字段的部分更新不再误删自定义气泡位图；content 解码失败补记日志
  - `zoomByFocus` 先按 min/max 钳制出有效缩放量再换算焦点，消除相机在极值处缩放时焦点漂移
  - `mapId` 缺失时 fail-fast 抛异常（旧实现静默回退 -1，多实例会串台）
  - 新增 nativeId→dartId 反向索引，marker 点击/拖拽/气泡回调反查由 O(n) 降为 O(1)；`onDetachedFromEngine` 逐个 dispose 遗留视图防通道 handler 泄漏
- **新增地图语言切换**：`AMapWidget.language`（`MapLanguage.chinese` / `.english`，创建参数 + `didUpdateWidget` 差量下发 `map#setLanguage`）、`AMapController.setLanguage()`；Android 映射 `AMap.setMapLanguage(CHINESE/ENGLISH)`、iOS 映射 `MAMapView.mapLanguage`（NSNumber 0/1）。注意 SDK 限制：英文仅标准地图类型生效、与自定义样式互斥
- **修复 iOS 地图蓝屏（真根因定案）**：`applyLimitBounds(null)` 曾在建图时把 `limitMapRect` 设为零矩形——其语义是「可见区域矩形边界」，零矩形即钳制到世界原点（85.05N/-180W）并触发 SDK 强制 zoom 适配（持续衰减）→ 整屏海面。此前误诊为 SDK 11.x 的 iOS 26 bug。现仅非零矩形才设置 limit，解除时以全世界矩形恢复（10.1.600 / 11.3.100 双版本真机验证）
- **手势开关动态更新**：`didUpdateWidget` 差量下发 `map#setGestures`（Android `applyGestures`、iOS `applyGestures` 共用创建/动态两条路径），手势不再仅创建时生效
- **修复 `CameraUpdate.zoomByFocus`**：Android 原生端此前未实现该 op（静默失败），现以投影换算模拟（焦点地理坐标保持屏幕不动）；iOS 直接映射 `MACameraUpdate.zoomBy(_:focus:)`
- example 全面细化：地图配置页改为纯动态更新（去掉 ValueKey，新增路况/建筑/标注/指南针/比例尺/POI 开关与 limitBounds）；覆盖物页新增图标工厂（fromAssetImage / fromIconPath / defaultMarkerWithHue）、anchor / flat / visible / zIndex 切换、showInfoWindow / hideInfoWindow、geodesic 大地曲线、customTexture 纹理线、虚线样式循环；新增「自定义气泡」（renderWidgetToPng + InfoWindow.content）与「自定义地图样式」两页；事件页补 onLongPress 与 AMapUtil 距离测量；相机页补 zoomIn / zoomOut / zoomByFocus

M0 技术验证 + MVP 覆盖物引擎：

- 单包架构：Dart 层（model / overlay / widget / controller / config / util 分层）+ Android (Kotlin) + iOS (Swift)
- `AMapInitializer.init`：Dart 侧 ApiKey 注入 + 隐私合规状态同步（Android `MapsInitializer`、iOS `AMapServices`/`MAMapView` 合规接口）
- `AMapWidget`：Hybrid Composition 地图渲染（Android）、UiKitView（iOS）
- **覆盖物差量更新引擎**（MarkerUpdates 模式）：`MarkerUpdates` / `PolylineUpdates` / `PolygonUpdates` / `CircleUpdates` diff，`didUpdateWidget` 仅下发增/删/改三部分，双端原生按 id 增删改
- **覆盖物交互**：Marker 点击（`onMarkerTap` + `Marker.onTap`）、InfoWindow 点击（`onInfoWindowTap` + `InfoWindow.onTap`）、Marker 拖拽结束（`onMarkerDragEnd` + `Marker.onDragEnd`）
- `AMapController`：`moveCamera` / `animateCamera`、相机查询、审图号查询、`takeSnapshot`
- `CameraUpdate` 7 种工厂（newLatLng / newLatLngZoom / newLatLngBounds / newCameraPosition / zoomTo / zoomBy / scrollBy）
- 基础模型：`LatLng` / `LatLngBounds` / `CameraPosition` / `MapType`
- **P0 相机限制模型**：`MinMaxZoomPreference` / `CameraTargetBounds`（替代 minZoom/maxZoom 双精度参数），支持创建时与动态更新
- **手势开关**（US-04）：`zoomGesturesEnabled` / `scrollGesturesEnabled` / `rotateGesturesEnabled` / `tiltGesturesEnabled`
- **P1 能力**：`MyLocationStyleOptions`（蓝点样式与 5 种定位模式）、`CustomStyleOptions`（官方样式 ID）、`AMapPoi` + `onPoiTapped`
- 地图加载完成回调（`onMapLoaded`）、地图截图（Android）
- **自定义 InfoWindow**：`InfoWindow.content`（BitmapDescriptor 图片替换整个气泡窗口）+ `renderWidgetToPng`（任意 Flutter Widget → PNG 截图）+ `AMapController.showInfoWindow` / `hideInfoWindow`（Android `setInfoWindowAdapter`，iOS `customCalloutView`，均为静态快照、不支持内部交互）
- **几何运算工具 `GeometryUtil`**（基于 clipper2）：`xorCircles` / `xorPolygons` / `xorCirclePolygon` 计算两形状的「不相交区域」（对称差 XOR），返回可直接渲染的 `Polygon` 列表（含孔洞，经纬度平面近似，适用于城市级小范围）；`circleToPoints` 圆→多边形近似
- `Polygon` 新增 `holes` 孔洞环支持（Android `PolygonHoleOptions`，iOS `initWithCoordinates:count:interiorPolygons:` 需 macOS 构建验证）
- example 重构为多页 demo（首页功能列表）：地图类型/手势、覆盖物管理（含 fromBytes 运行时图标、拖拽、气泡点击、**自定义气泡**）、相机控制（7 工厂 + 实时状态）、**几何运算 XOR 演示页**、事件日志、定位蓝点模式切换、截图与审图号；example 启动时请求定位权限

- 覆盖物模型（sealed）：`Marker` / `Polyline` / `Polygon` / `Circle`，含 `BitmapDescriptor`（default / asset / bytes）、`InfoWindow`

已注明的平台差异（后续版本补齐）：iOS 暂不支持 CameraTargetBounds / 虚线细分样式 / capType / joinType / rotation / alpha / zIndex / takeSnapshot / MyLocationStyle 样式与自定义样式（Android 已支持，iOS 需在 macOS 构建时按 AMap3DMap 实际 API 补齐）；倾斜手势 iOS 属性名待验证。
