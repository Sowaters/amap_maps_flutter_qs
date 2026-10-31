# MIGRATION：从官方 `amap_flutter_map` 迁移到 `amap_maps_flutter_qs`

本插件（`amap_maps_flutter_qs`）的 API 形状以官方 `amap_flutter_map` 3.0.0
为基线对齐：**大部分类名、方法名、参数名可以直接沿用**。本文列出全部
已知差异，按「必须改」「建议改」「本插件扩展」三档组织。

## 1. 初始化方式（必须改）

官方通过 `AMapWidget` 构造参数配置 Key 与隐私合规；本插件改为**全局一次式**
`AMapInitializer.init`（需在 `runApp` 前调用）：

```dart
// 官方写法（已废弃）
AMapWidget(
  apiKey: const AMapApiKey(androidKey: '...', iosKey: '...'),
  privacyStatement: const AMapPrivacyStatement(hasContains: true, hasShow: true, hasAgree: true),
)

// 本插件写法
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AMapInitializer.init(
    apiKey: const AMapApiKey(androidKey: '...', iosKey: '...'),
    privacyStatement: const AMapPrivacyStatement(hasContains: true, hasShow: true, hasAgree: true),
  );
  runApp(const MyApp());
}
```

`AMapApiKey` / `AMapPrivacyStatement` 两个类保持官方形状，只是不再挂在
`AMapWidget` 上。

## 2. 覆盖物构造（必须改）

覆盖物构造时 **`id` 可省略**（自动生成），与官方一致；原来必填 id 的旧代码
只需删掉 `required` 感受——直接删 `id:` 参数即可，或保留自定义 id 也能工作。

```dart
// 官方 / 本插件（一致）
Marker(position: LatLng(39.9, 116.4))
Polyline(points: [...])
Polygon(points: [...])
```

## 3. `copyWith` 参数名（必须改）

本插件对齐官方的 `Param` 后缀约定：

| 官方 / 本插件（新） | 本插件旧名 |
| --- | --- |
| `copyWith(positionParam: ...)` | `position` |
| `copyWith(iconParam: ...)` | `icon` |
| `copyWith(infoWindowParam: ...)` | `infoWindow` |
| `copyWith(pointsParam: ...)` | `points` |
| `copyWith(fillColorParam: ...)` / `strokeColorParam` | `fillColor` / `strokeColor` |
| `copyWith(radiusParam: ...)` | `radius` |
| `copyWith(holesParam: ...)` | `holes` |
| `copyWith(alphaParam: ...)` / `rotationParam` / `zIndexParam` / `visibleParam` | 同名无后缀 |

与官方一致的限制：`Polyline.joinType` / `Polygon.joinType` 不可通过
`copyWith` 修改（仅初始化时设置一次）。

## 4. AMapWidget 参数（部分必须改）

### 4.1 完全对齐官方（名字、默认值都一致）

`initialCameraPosition`（可不传，默认北京中心 zoom 10）、`mapType`、
`minMaxZoomPreference`、`limitBounds`、`trafficEnabled`（默认 false）、
`touchPoiEnabled`（默认 true）、`buildingsEnabled`（默认 true）、
`labelsEnabled`（默认 true）、`compassEnabled`（默认 false）、
`scaleEnabled`（默认 true）、四个手势开关、`markers` / `polylines` /
`polygons`、`onMapCreated` / `onCameraMove` / `onCameraMoveEnd` / `onTap` /
`onLongPress`、`onPoiTouched`（需 `touchPoiEnabled`）、`customStyleOptions`、
`myLocationStyleOptions`、`gestureRecognizers`。

### 4.2 需要改名

| 官方 | 本插件 | 说明 |
| --- | --- | --- |
| `limitBounds: LatLngBounds(...)` | 同名 ✓ | 旧版本插件的 `cameraTargetBounds: CameraTargetBounds(...)` 已废弃 |
| `onPoiTouched` | 同名 ✓ | 旧版本插件的 `onPoiTapped` 已废弃（仍可用） |

### 4.3 本插件扩展（官方没有，按需使用）

- `circles`：Circle 覆盖物集合（官方插件无 Circle）
- `onMarkerTap` / `onInfoWindowTap` / `onMarkerDragEnd` / `onMapLoaded`
- `myLocationEnabled`：独立的蓝点总开关
- `Marker.infoWindowEnable`：false 时点击 Marker 永不弹气泡
- `Marker.flat` / `Marker.alpha` / `Marker.clickable`
- `Polygon.holes` / `Polygon.hollow`（孔洞与镂空）
- `MyLocationStyleOptions.locationMode`（见下）

## 5. 相机控制（必须改）

官方 `moveCamera` 签名已完整对齐：

```dart
// 官方与插件一致
controller.moveCamera(update, animated: true, duration: 250); // 默认值
controller.moveCamera(update, animated: false);               // 无动画
```

注意：本插件 `moveCamera` 的 `animated` **默认 true**（与官方一致），
老版本插件默认无动画——依赖旧行为的代码请显式传 `animated: false`。
旧 `animateCamera(update, duration: Duration)` 已废弃，仍可用。

`CameraUpdate` 全部工厂与官方一致：`newCameraPosition` / `newLatLng` /
`newLatLngZoom` / `newLatLngBounds` / `zoomTo` / `zoomBy` / `zoomIn` /
`zoomOut` / `scrollBy`。本插件额外提供 `zoomByFocus`。

## 6. BitmapDescriptor（必须改）

官方工厂全部可用：

```dart
BitmapDescriptor.defaultMarker
BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange)
BitmapDescriptor.fromIconPath('assets/marker.png')          // 官方最常用
await BitmapDescriptor.fromAssetImage(configuration, 'assets/a.png')
BitmapDescriptor.fromBytes(pngBytes)
```

本插件旧 API 仍可用但已废弃：`defaultIcon` → `defaultMarker`、
`fromAsset` → `fromIconPath`。色相常量（`hueRed` ~ `hueRose`）与官方一致。

平台差异：`defaultMarkerWithHue` 在 iOS 上回退为 SDK 默认大头针
（iOS SDK 无色相着色等价 API）。

## 7. Polyline 新能力（对齐官方）

```dart
Polyline(
  points: [...],
  geodesic: true,                                        // 大地曲线
  customTexture: BitmapDescriptor.fromIconPath('...'),   // 纹理线
)
```

默认值对齐官方：宽度 10、颜色 `0xCCC4E0F0`、`joinType: JoinType.bevel`。
`Polygon` 默认色也对齐官方（边框 `0xCC00BFFF`、填充 `0xC487CEFA`）。

## 8. 样式类构造（必须改）

### MyLocationStyleOptions

对齐官方：首位位置参数控制蓝点开关。

```dart
// 官方 / 本插件（新）
MyLocationStyleOptions(true, circleFillColor: ..., circleStrokeColor: ...)

// 本插件旧写法（已移除）：MyLocationStyleOptions(enabled: ..., accuracyCircleFillColor: ...)
```

本插件扩展参数 `locationMode`（`MyLocationMode` 枚举，映射原生
`myLocationType`）保持不变。

### CustomStyleOptions

对齐官方：本地样式二进制模式。

```dart
// 读取高德控制台下载的自定义地图包
final styleData = (await rootBundle.load('styles/style.data')).buffer.asUint8List();
final styleExtraData = (await rootBundle.load('styles/style_extra.data')).buffer.asUint8List();
CustomStyleOptions(true, styleData: styleData, styleExtraData: styleExtraData);

// 本插件扩展：云端样式 ID 模式
CustomStyleOptions(true, customStyleId: 'your-style-id');
```

两种模式二选一，同时设置时本地二进制数据优先。当前 iOS 端
自定义样式尚未对接（TODO），Android 端两种模式均已实现。

## 9. 保留差异（设计决策，不会对齐）

| 项 | 官方 | 本插件 | 原因 |
| --- | --- | --- | --- |
| 包结构 | `amap_flutter_map` + `amap_flutter_base` 双包 | 单包 | 简化依赖（PRD 决策） |
| 初始化 | `AMapWidget` 构造参数 | `AMapInitializer.init` | Key/合规全局一次性配置 |
| `onLocationChanged` | `AMapWidget` 参数 | 不提供 | 定位属 `AMapLocation` 域，PRD 明确不并入 |
| 覆盖物类型 | 继承体系 | Dart 3 密封类 `MapObject` | `switch` 穷尽匹配，新增类型编译期强制 |
| 更新机制 | 全量/由官方内部 diff | `MarkerUpdates` 等显式差量 | 可测试、可预览 payload |
| `setRenderFps` | 有 | 暂未提供 | 后续版本 |

## 10. 已知平台差异

- `CameraUpdate.newLatLngBounds` 在 iOS 上使用 SDK `fitBounds`，padding 参数
  在 iOS 上不生效
- `Polyline.capType` / `joinType` 为 Android 专属，iOS 使用 SDK 默认值
- `CameraUpdate.zoomIn/zoomOut` 在 iOS 上以 `zoomBy(±1)` 等价实现
- 地图中心点范围限制（`limitBounds`）当前仅 Android 生效，iOS 为 no-op（TODO）
