# amap_maps_flutter_qs

高德地图（AMap / Gaode）3D 地图 Flutter 插件。

> 官方 `amap_flutter_map` 自 2021 年停止维护（不兼容 Flutter 3.x / AGP 7+ / x86_64 模拟器），
> 本插件是其现代化继任者：单包架构、Dart 3 密封类覆盖物、隐私合规 API 齐全。
>
> 当前版本 `0.0.1`：MVP 能力已齐（覆盖物差量更新引擎 + 事件全量 + 自定义气泡 + 几何运算），
> iOS 个别能力尚在补齐中（见[平台差异](#平台差异)）。API 可能随版本调整。

## 特性

- ✅ `AMapWidget` 地图渲染（Android Hybrid Composition 兼容 GLSurfaceView，iOS UiKitView）
- ✅ `AMapInitializer.init`：ApiKey + 隐私合规一站式 Dart 侧初始化
- ✅ `AMapController` 相机控制：`moveCamera(update, animated, duration)` + **10 种 `CameraUpdate` 工厂**
  （`newLatLng` / `newLatLngZoom` / `newLatLngBounds` / `newCameraPosition` / `zoomTo` / `zoomBy` /
  `zoomIn` / `zoomOut` / `zoomByFocus` / `scrollBy`），其中 `zoomByFocus` Android 端以投影换算模拟实现
- ✅ 覆盖物 Marker / Polyline / Polygon / Circle，声明式差量更新
  （`MarkerUpdates` / `PolylineUpdates` / `PolygonUpdates` / `CircleUpdates`，仅下发增/删/改）
- ✅ `BitmapDescriptor` 全量工厂（`defaultMarkerWithHue` / `fromIconPath` / `fromAssetImage` / `fromBytes`）
- ✅ Polyline 纹理线（`customTexture`）与大地曲线（`geodesic`）、虚线样式；Polygon 孔洞（`holes`）
- ✅ 地图事件全量：点击 / 长按 / POI（`onPoiTouched`）/ Marker 点击与拖拽 /
  InfoWindow 点击 / 相机移动（`onCameraMove` / `onCameraMoveEnd`）/ 加载完成（`onMapLoaded`）
- ✅ UI 开关（路况 / POI 点击 / 建筑物 / 标注 / 指南针 / 比例尺）与四类手势开关，
  **均支持创建时与 `didUpdateWidget` 动态更新**
- ✅ 相机限制：`MinMaxZoomPreference`（缩放级别范围）与 `limitBounds`（可视范围限制，动态更新）
- ✅ 定位蓝点（`MyLocationStyleOptions`，五种模式）
- ✅ 自定义地图样式（官方本地 `styleData` 二进制 + 云端样式 ID 双模式，Android）
- ✅ **自定义气泡**：`InfoWindow.content`（图片替换整个气泡）+ `renderWidgetToPng`
  （任意 Flutter Widget → PNG 截图）+ `controller.showInfoWindow` / `hideInfoWindow`
- ✅ **几何运算工具 `GeometryUtil`**（基于 clipper2）：`xorCircles` / `xorPolygons` / `xorCirclePolygon`
  计算两形状互斥区域（XOR），返回含孔洞、可直接渲染的 `Polygon` 列表
- ✅ **距离测量 `AMapUtil`**：`distanceBetween`（haversine 球面距离）、`distanceToBounds`
- ✅ 地图截图 `takeSnapshot`、可视区域查询 `getVisibleRegion`、审图号查询（普通 / 卫星）

> API 形状与官方 `amap_flutter_map` 3.0.0 对齐，从官方迁移见
> [MIGRATION.md](https://github.com/Sowaters/amap_maps_flutter_qs/blob/master/MIGRATION.md)。

## 平台要求

| 平台 | 最低版本 | 地图 SDK |
| --- | --- | --- |
| Android | minSdk 24 | AMap3DMap/Search/Location **11.3.100** 官方离线包（jar + so 已随插件分发；11.x 未上 mavenCentral） |
| iOS | 13.0 | AMap3DMap pod `~> 11.2`（CocoaPods trunk） |

支持 ABI：`armeabi-v7a` / `arm64-v8a`。**离线包不含 x86_64 切片，Android 模拟器无法运行地图，请使用真机调试。**

## 快速开始

### 1. 申请 Key

在[高德开放平台](https://console.amap.com)申请：
- Android：按「包名 + 签名 SHA1」
- iOS：按 BundleID

### 2. 初始化（必须早于任何地图 Widget）

```dart
import 'package:amap_maps_flutter_qs/amap_maps_flutter_qs.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AMapInitializer.init(
    apiKey: const AMapApiKey(
      androidKey: 'YOUR_ANDROID_KEY',
      iosKey: 'YOUR_IOS_KEY',
    ),
    privacyStatement: const AMapPrivacyStatement(
      hasContains: true, // 隐私弹窗包含高德隐私条款
      hasShow: true,     // 已展示隐私弹窗
      hasAgree: true,    // 用户已同意 —— 必须在用户真实同意后置 true
    ),
  );
  runApp(const MyApp());
}
```

> ⚠️ 合规要求：宿主 App 必须先弹隐私授权窗，用户同意后再传真实状态，
> 否则 SDK 按未授权处理（地图不渲染）。Android Key 也可以改用
> `AndroidManifest.xml` 中 `com.amap.api.v2.apikey` meta-data 配置。

### 3. 展示地图

```dart
const AMapWidget(
  initialCameraPosition: CameraPosition(
    target: LatLng(39.909187, 116.397451),
    zoom: 10,
  ),
)
```

### 4. 相机控制与覆盖物

```dart
AMapWidget(
  // initialCameraPosition 可省略（默认北京中心 zoom 10）
  onMapCreated: (controller) {
    // 与官方一致：animated 默认 true，duration 默认 250ms
    controller.moveCamera(
      CameraUpdate.newLatLngZoom(const LatLng(31.230416, 121.473701), 12),
    );
  },
  markers: {
    Marker(
      position: const LatLng(39.909187, 116.397451), // id 可省略，自动生成
      icon: BitmapDescriptor.fromIconPath('assets/marker.png'),
      infoWindow: const InfoWindow(title: '天安门'),
      onDragEnd: (id, pos) => print('拖拽到 $pos'),
    ),
  },
  polylines: {
    Polyline(
      points: const [LatLng(39.9, 116.4), LatLng(31.2, 121.5)],
      geodesic: true, // 大地曲线
    ),
  },
  polygons: {Polygon(points: [...], holes: [[...]])}, // 支持孔洞
)
```

### 5. 自定义气泡（Widget → PNG）

```dart
// 1. 把任意 Flutter Widget 渲染为 PNG（屏幕外截图，静态快照；
//    返回快照的 png 字节 + 逻辑尺寸）
final snapshot = await renderWidgetToPng(context, const Card(child: Text('自定义气泡')));
// 2. 作为整个气泡窗口内容（务必带上逻辑尺寸，否则 iOS 会把
//    pixelRatio 3 的 PNG 物理像素当点显示、放大 3 倍）
final marker = Marker(
  position: pos,
  infoWindow: InfoWindow(
    content: BitmapDescriptor.fromBytes(
      snapshot.png,
      width: snapshot.width,
      height: snapshot.height,
    ),
  ),
);
// 3. 手动控制显隐
await controller.showInfoWindow(marker.id);
await controller.hideInfoWindow(marker.id);
```

### 6. 几何运算（互斥区域 XOR）

```dart
// 两圆的「不相交区域」，返回含孔洞、可直接上图的 Polygon 列表
final rings = GeometryUtil.xorCircles(circleA, circleB);
setState(() => polygons.addAll(rings));

// 距离测量
final meters = AMapUtil.distanceBetween(beiJing, shangHai);
```

> ⚠️ `GeometryUtil` 以经纬度作为平面坐标运算，适用于城市级小范围场景。

完整示例见 [example/](example/)（多页 demo：地图配置 / 覆盖物管理 / 相机控制 /
几何运算 / 事件日志 / 定位蓝点 / 截图与审图号 / 自定义气泡 / 自定义地图样式）；
从官方 `amap_flutter_map` 迁移指南见
[MIGRATION.md](https://github.com/Sowaters/amap_maps_flutter_qs/blob/master/MIGRATION.md)。

## 平台差异

| 能力 | Android | iOS |
| --- | --- | --- |
| 自定义地图样式（`customStyleOptions`） | ✅ | ✅ |
| 定位蓝点样式（`myLocationStyleOptions` 完整样式） | ✅ | ✅ |
| 地图截图 `takeSnapshot` | ✅ | ✅ |
| Polyline 纹理线（`customTexture`）/ capType（含 arrow）/ joinType | ✅ | ✅ |
| Marker `rotation` / `zIndex`（`alpha` 双端已支持） | ✅ | 待补齐 |

其余特性（覆盖物 / 事件 / 相机 / 手势 / UI 开关 / `limitBounds` / 审图号等）双端一致。

## 合规注意

- 地图页面需展示**审图号**：`controller.getMapContentApprovalNumber()`（普通地图）、
  `controller.getSatelliteImageApprovalNumber()`（卫星地图）
  （Android 查询；iOS 由 SDK 在地图上自动展示）
- 隐私合规方案：<https://lbs.amap.com/news/sdkhgsy>
- 本插件为社区插件，与高德官方无隶属关系

## 第三方组件声明

- 本插件为独立开发的社区作品，与高德官方无隶属关系，亦未使用高德官方
  `amap_flutter_map` 的源码（仅 API 形状对齐以方便迁移）。
- Android 端随包分发了高德官方 SDK 离线包（`AMap3DMap 11.3.100` /
  `AMapSearch 9.8.1` / `AMapLocation 11.3.101` 的 jar 与 so）。该 SDK 的著作权
  归属高德软件（AutoNavi / AMap），其获取与使用须遵守
  [高德开放平台服务协议](https://lbs.amap.com/home/terms/)；iOS 端则通过
  CocoaPods 官方渠道（trunk）分发，不在本包内携带。
- 使用本插件即表示您已按高德要求注册开发者账号、申请合法 Key，并在 App 内
  落地隐私合规（弹窗展示与用户同意）。

## Roadmap

- [x] M0：地图渲染 + 相机 + 事件
- [x] MVP（0.0.1）：覆盖物差量更新、事件全量、手势/UI 开关动态更新、
  自定义气泡、几何运算 XOR、`limitBounds`、`zoomByFocus`（当前）
- [x] iOS 平台差异补齐：takeSnapshot / poiTap / infoWindowTap / 蓝点样式 / 自定义地图样式
- [ ] v1.1：Marker `rotation` / `zIndex` 的 iOS 对接、AMapUtil 扩展
- [ ] v2.0：独立服务插件（搜索 / 地理编码）

## License

MIT
