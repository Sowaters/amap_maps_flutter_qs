import 'latlng.dart';

/// 地图上的兴趣点（POI，PRD US-04 事件流 / §4.2 P1）。
///
/// 由原生地图点击 POI 时回传，用于 [AMapWidget.onPoiTapped]。
class AMapPoi {
  /// POI 唯一标识（原生 SDK 可能返回空串）。
  final String id;

  /// POI 名称。
  final String name;

  /// POI 坐标。
  final LatLng? position;

  const AMapPoi({required this.id, required this.name, this.position});

  /// 从通道消息反序列化。
  static AMapPoi? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'] as String?;
    if (name == null) return null;
    return AMapPoi(
      id: (json['id'] as String?) ?? '',
      name: name,
      position: LatLng.fromJson(json['position']),
    );
  }

  /// 序列化。
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    if (position != null) 'position': position!.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AMapPoi && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);

  @override
  String toString() => 'AMapPoi($name)';
}
