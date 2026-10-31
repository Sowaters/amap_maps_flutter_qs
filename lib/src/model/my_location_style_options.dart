import 'dart:ui';

import '../overlay/overlay.dart';

/// 定位蓝点模式（对齐原生 `MyLocationStyle.myLocationType`）。
enum MyLocationMode {
  /// 只定位（首次定位移动到中心，仅显示蓝点）。
  show,

  /// 定位且移动到中心。
  locate,

  /// 跟随（蓝点始终在地图中心）。
  follow,

  /// 罗盘模式（随地图旋转，蓝点仍在中心）。
  mapRotate,

  /// 定位方向旋转（蓝点随设备朝向旋转）。
  locationRotate;

  /// 原生 SDK 对应常量（Android `MyLocationStyle.LOCATION_TYPE_*`）。
  int get nativeCode => switch (this) {
    MyLocationMode.show => 0,
    MyLocationMode.locate => 1,
    MyLocationMode.follow => 2,
    MyLocationMode.mapRotate => 3,
    MyLocationMode.locationRotate => 4,
  };

  /// 通道序列化。
  Object toJson() => name;
}

/// 定位蓝点样式。
///
/// 构造签名对齐官方 `amap_flutter_map` 的 `MyLocationStyleOptions`：
/// 首位位置参数 [enabled] 控制是否显示小蓝点；[locationMode] 为本插件
/// 扩展（官方无对应参数）。
class MyLocationStyleOptions {
  /// 是否显示定位小蓝点。
  final bool enabled;

  /// 精度圈填充色。
  final Color? circleFillColor;

  /// 精度圈边框色。
  final Color? circleStrokeColor;

  /// 精度圈边框宽度（dp）。
  final double? circleStrokeWidth;

  /// 小蓝点图标（null 时用 SDK 默认）。
  final BitmapDescriptor? icon;

  /// 蓝点模式（本插件扩展，官方无对应参数）。
  final MyLocationMode locationMode;

  const MyLocationStyleOptions(
    this.enabled, {
    this.circleFillColor,
    this.circleStrokeColor,
    this.circleStrokeWidth,
    this.icon,
    this.locationMode = MyLocationMode.locate,
  });

  /// 序列化（回调不传输）。
  Map<String, Object?> toJson() => <String, Object?>{
    'enabled': enabled,
    'circleFillColor': circleFillColor?.toARGB32(),
    'circleStrokeColor': circleStrokeColor?.toARGB32(),
    'circleStrokeWidth': circleStrokeWidth,
    'icon': icon?.toJson(),
    'locationMode': locationMode.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MyLocationStyleOptions &&
          other.enabled == enabled &&
          other.circleFillColor == circleFillColor &&
          other.circleStrokeColor == circleStrokeColor &&
          other.circleStrokeWidth == circleStrokeWidth &&
          other.icon == icon &&
          other.locationMode == locationMode;

  @override
  int get hashCode => Object.hash(
    enabled,
    circleFillColor,
    circleStrokeColor,
    circleStrokeWidth,
    icon,
    locationMode,
  );

  @override
  String toString() =>
      'MyLocationStyleOptions($enabled, $locationMode)';
}
