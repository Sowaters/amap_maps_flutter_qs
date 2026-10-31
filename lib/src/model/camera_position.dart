import 'latlng.dart';

/// 相机位置：可视区域的完整状态。
class CameraPosition {
  /// 地图中心点。
  final LatLng target;

  /// 缩放级别，范围 [3.0, 20.0]。
  final double zoom;

  /// 俯仰角（倾斜角度），范围 [0.0, 45.0]。
  final double tilt;

  /// 旋转角度（从正北顺时针），范围 [0.0, 360.0)。
  final double bearing;

  const CameraPosition({
    required this.target,
    this.zoom = 10.0,
    this.tilt = 0.0,
    this.bearing = 0.0,
  });

  /// 从通道消息反序列化。
  static CameraPosition? fromJson(Object? json) {
    if (json is Map) {
      final target = LatLng.fromJson(json['target']);
      if (target == null) return null;
      return CameraPosition(
        target: target,
        zoom: (json['zoom'] as num?)?.toDouble() ?? 10.0,
        tilt: (json['tilt'] as num?)?.toDouble() ?? 0.0,
        bearing: (json['bearing'] as num?)?.toDouble() ?? 0.0,
      );
    }
    return null;
  }

  /// 序列化。
  Map<String, Object?> toJson() => <String, Object?>{
    'target': target.toJson(),
    'zoom': zoom,
    'tilt': tilt,
    'bearing': bearing,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CameraPosition &&
          other.target == target &&
          other.zoom == zoom &&
          other.tilt == tilt &&
          other.bearing == bearing;

  @override
  int get hashCode => Object.hash(target, zoom, tilt, bearing);

  @override
  String toString() =>
      'CameraPosition(target: $target, zoom: $zoom, tilt: $tilt, bearing: $bearing)';
}
