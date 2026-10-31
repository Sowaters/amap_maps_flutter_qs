## Unreleased

- **手势开关动态更新**：`didUpdateWidget` 差量下发 `map#setGestures`（Android `applyGestures`、iOS `applyGestures` 共用创建/动态两条路径），手势不再仅创建时生效
- **修复 `CameraUpdate.zoomByFocus`**：Android 原生端此前未实现该 op（静默失败），现以投影换算模拟（焦点地理坐标保持屏幕不动）；iOS 直接映射 `MACameraUpdate.zoomBy(_:focus:)`
- example 全面细化：地图配置页改为纯动态更新（去掉 ValueKey，新增路况/建筑/标注/指南针/比例尺/POI 开关与 limitBounds）；覆盖物页新增图标工厂（fromAssetImage / fromIconPath / defaultMarkerWithHue）、anchor / flat / visible / zIndex 切换、showInfoWindow / hideInfoWindow、geodesic 大地曲线、customTexture 纹理线、虚线样式循环；新增「自定义气泡」（renderWidgetToPng + InfoWindow.content）与「自定义地图样式」两页；事件页补 onLongPress 与 AMapUtil 距离测量；相机页补 zoomIn / zoomOut / zoomByFocus

## 0.0.1

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
