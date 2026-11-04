## 0.1.3

### 修复

- **Android release 构建开启 R8（minify）不再失败**：高德合包 SDK 在
  mavenCentral 以纯 JAR 分发，无法自带 consumer proguard 规则，R8 会因
  引用可选 GNSS 模块（`com.amap.ams.gnss.*`）报 Missing class。
  插件现内置 `consumerProguardFiles`（dontwarn + keep `com.amap.**` /
  `com.autonavi.**`），使用者**无需再自行配置任何 proguard 规则**
- example 常驻开启 R8 作为回归验证

## 0.1.2

### 文档

- README iOS 章节新增「SwiftPM 说明」：插件暂不支持 SwiftPM 的原因
  （`AMap3DMap` 仅 CocoaPods trunk 分发）、开启 SwiftPM 集成时的
  CocoaPods 自动回退行为与影响

## 0.1.1

### 文档

- README iOS 章节补充 Podfile 要求：高德 `AMap3DMap` 为静态 framework，
  宿主 Podfile 含 `use_frameworks!`（Flutter 新模板可能默认启用）会导致
  `pod install` 失败且报错难定位，需移除该行并确保
  `platform :ios, '13.0'`；确有依赖需要 frameworks 时改用
  `use_frameworks! :linkage => :static`
- README 新增「权限说明」章节：双端权限矩阵（地图显示 / 定位蓝点）、
  Android Manifest 声明与运行时授权（permission_handler 示例）、
  iOS `Info.plist` 用途描述声明

## 0.1.0

首个发布版本。单包架构（Dart 层 + Android Kotlin + iOS Swift），API 形状与官方
`amap_flutter_map` 3.0.0 对齐，便于从官方插件平滑迁移。

### 地图与初始化

- `AMapInitializer.init`：Dart 侧 ApiKey 注入 + 隐私合规状态一站式同步
  （Android `MapsInitializer`、iOS `AMapServices` / `MAMapView` 合规接口）
- `AMapWidget` 地图渲染（Android Hybrid Composition、iOS UiKitView）
- **地图语言切换**：`AMapWidget.language`（中/英，创建与动态更新）+
  `AMapController.setLanguage()`。SDK 限制：英文仅标准地图类型生效、与自定义样式互斥
- 相机控制：`moveCamera` / `animateCamera` + 10 种 `CameraUpdate` 工厂
  （`newLatLng` / `newLatLngZoom` / `newLatLngBounds` / `newCameraPosition` /
  `zoomTo` / `zoomBy` / `zoomIn` / `zoomOut` / `zoomByFocus` / `scrollBy`），
  `zoomByFocus` Android 以投影换算模拟、iOS 映射原生 `zoomBy(_:focus:)`
- 相机限制：`MinMaxZoomPreference` / `CameraTargetBounds` / `limitBounds`，
  均支持创建时与动态更新
- 手势开关（缩放/平移/旋转/倾斜）与 UI 开关（路况 / POI / 建筑 / 标注 / 指南针 /
  比例尺），均支持 `didUpdateWidget` 动态更新
- 定位蓝点（`MyLocationStyleOptions` 五种模式）、自定义地图样式（本地 `styleData`
  二进制 + 云端样式 ID）
- 地图事件全量：点击 / 长按 / POI / Marker 点击与拖拽 / InfoWindow 点击 /
  相机移动（`onCameraMove` / `onCameraMoveEnd`）/ 加载完成（`onMapLoaded`）
- 地图截图 `takeSnapshot`、可视区域查询 `getVisibleRegion`、审图号查询（普通 / 卫星）

### 覆盖物

- **差量更新引擎**：`MarkerUpdates` / `PolylineUpdates` / `PolygonUpdates` /
  `CircleUpdates` diff，`didUpdateWidget` 仅下发增/删/改三部分
- `BitmapDescriptor` 全量工厂（`defaultMarkerWithHue` / `fromIconPath` /
  `fromAssetImage` / `fromBytes`）；Polyline 纹理线（`customTexture`）、
  大地曲线（`geodesic`）、虚线样式；Polygon 孔洞（`holes`）
- **自定义气泡**：`InfoWindow.content`（图片替换整个气泡）+
  `renderWidgetToPng`（任意 Flutter Widget → PNG）+
  `controller.showInfoWindow` / `hideInfoWindow`
- **几何运算 `GeometryUtil`**（基于 clipper2）：`xorCircles` / `xorPolygons` /
  `xorCirclePolygon` 计算互斥区域（XOR），返回含孔洞、可直接渲染的 `Polygon` 列表
- 距离测量 `AMapUtil.distanceBetween` / `distanceToBounds`

### 修复与整改

- **修复 iOS 建图蓝屏（真根因定案）**：`limitBounds(null)` 曾在建图时把
  `limitMapRect` 设为零矩形（其语义是「可见区域矩形边界」，零矩形即钳制到
  世界原点并触发强制缩放适配）→ 整屏海面。现仅非零矩形才设置 limit，
  解除时以全世界矩形恢复（10.1.600 / 11.3.100 双版本真机验证）
- Android 气泡 tap-to-dismiss 对齐 iOS 原生 deselect 行为：地图空白点击时
  主动关闭当前气泡，所有显隐入口统一同步追踪状态
- 双端 `scrollBy` / `zoomByFocus` 单位语义修正为 Flutter 逻辑像素
  （旧实现 3x 设备上实际滚动/焦点距离仅约请求量的 1/3）
- 双端 `takeSnapshot` / 相机回调保证恰好应答一次（地图 dispose 后不再悬挂 Future）
- iOS 代码审查整改：`viewFor` 复用池视图无条件重置视觉属性（消除残留）、
  selection 残留清理、`newLatLngBounds` 退化矩形守卫、初始相机重设跳过守卫、
  `UIScreen.main` 弃用 API 全部替换等
- Android 代码审查整改：`updateMarker` 三处修复（`show=false` 关闭气泡、
  部分更新不再误删气泡位图）、`mapId` 缺失 fail-fast、
  反向索引 O(1) 回查与 handler 泄漏防护
- iOS：`MAMapView(frame:)` 返回 nil（常见于隐私合规未通过 / Key 未注入）时
  fail-fast 输出明确诊断，替代难以定位的 KVO 桥接 SIGABRT

### 分发与示例

- 双端 SDK 均经官方渠道分发，插件包零二进制：
  Android mavenCentral `com.amap.api:3dmap-location-search:11.3.100_loc11.3.101_sea9.8.1`，
  iOS CocoaPods trunk `AMap3DMap ~> 11.2`
- example 重构为多页 demo（地图配置 / 覆盖物管理 / 相机控制 / 几何运算 /
  事件日志 / 定位蓝点 / 截图与审图号 / 自定义气泡 / 自定义地图样式），
  Key 经 `--dart-define` 注入，仓库不含真实凭据
