import 'latlng_bounds.dart';

/// 地图中心点可视范围限制（对齐基线插件同名类）。
///
/// 已过时：[AMapWidget] 现使用官方命名的 `limitBounds`（`LatLngBounds?`）；
/// 本类仅为旧代码保留。
@Deprecated('Use LatLngBounds with AMapWidget.limitBounds instead')
class CameraTargetBounds {
  /// 限制范围，null 表示不限制。
  final LatLngBounds? bounds;

  const CameraTargetBounds(this.bounds);

  /// 不限制地图中心范围。
  static const CameraTargetBounds unbounded = CameraTargetBounds(null);

  /// 序列化。
  Object? toJson() => bounds?.toJson();

  /// 从通道消息反序列化（null / 空结构均视为 unbounded）。
  static CameraTargetBounds fromJson(Object? json) =>
      CameraTargetBounds(LatLngBounds.fromJson(json));

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CameraTargetBounds && other.bounds == bounds;

  @override
  int get hashCode => bounds.hashCode;

  @override
  String toString() => 'CameraTargetBounds($bounds)';
}
