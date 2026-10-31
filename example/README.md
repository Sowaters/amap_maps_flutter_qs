# amap_maps_flutter_qs demo

`amap_maps_flutter_qs` 插件的功能演示 App，按能力拆分为 6 个页面：

| 页面 | 演示内容 |
| --- | --- |
| 地图类型与基础控制 | `MapType` 五种类型切换、`MinMaxZoomPreference` 缩放范围、四种手势开关 |
| 覆盖物管理 | `Marker` 差量增删改、`BitmapDescriptor.fromBytes` 运行时图标、拖拽、`InfoWindow` 点击；`Polyline`（实线/虚线/cap/join）、`Polygon` 换色、`Circle` 半径调整 |
| 相机控制 | `CameraUpdate` 七种工厂、`moveCamera` / `animateCamera` 切换、实时相机状态与可视区域查询 |
| 地图事件 | `onTap` / `onPoiTapped` / `onMarkerTap` / `onInfoWindowTap` / `onMarkerDragEnd` / `onCameraMoveEnd` / `onMapLoaded` 事件日志 |
| 定位蓝点 | `MyLocationStyleOptions` 五种定位模式切换、精度圈颜色（需定位权限，启动时请求） |
| 截图与合规 | `takeSnapshot` 截图预览、审图号查询（上架合规展示） |

## 运行

1. 在 [`lib/demo_config.dart`](lib/demo_config.dart) 中填入你自己的高德 Key
   （Android 按「包名 + SHA1」申请，iOS 按 BundleID 申请）。
2. `flutter run`。

> ⚠️ Demo 中隐私合规直接声明为「已同意」，真实 App 必须先弹隐私弹窗、
> 用户同意后再调用 `AMapInitializer.init`。

## 已知平台差异

- `takeSnapshot`：仅 Android；iOS 后续版本支持。
- `CameraTargetBounds` / `MyLocationStyleOptions` 样式 / 自定义样式 / 虚线细分样式 /
  Marker rotation / alpha / zIndex：Android 完整支持，iOS 待补齐（详见插件 CHANGELOG）。
- 手势开关、缩放范围、蓝点样式当前在地图创建时生效（Demo 中通过切换重建地图验证），
  动态热更新随后续版本支持。
