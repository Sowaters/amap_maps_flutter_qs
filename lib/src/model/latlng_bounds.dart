import 'latlng.dart';

/// 经纬度对齐的矩形区域。
class LatLngBounds {
  /// 西南角（边界盒的最小经纬度）。
  final LatLng southwest;

  /// 东北角（边界盒的最大经纬度）。
  final LatLng northeast;

  /// 由西南角与东北角构造。
  ///
  /// 注意：southwest 必须在 northeast 的西南方向，否则原生渲染异常。
  const LatLngBounds({required this.southwest, required this.northeast});

  /// 区域中心点。
  LatLng get center => LatLng(
    (southwest.latitude + northeast.latitude) / 2,
    (southwest.longitude + northeast.longitude) / 2,
  );

  /// [point] 是否包含在本区域内（含边界）。
  bool contains(LatLng point) =>
      point.latitude >= southwest.latitude &&
      point.latitude <= northeast.latitude &&
      point.longitude >= southwest.longitude &&
      point.longitude <= northeast.longitude;

  /// 从通道消息反序列化。
  static LatLngBounds? fromJson(Object? json) {
    if (json is List && json.length == 2) {
      final sw = LatLng.fromJson(json[0]);
      final ne = LatLng.fromJson(json[1]);
      if (sw != null && ne != null) {
        return LatLngBounds(southwest: sw, northeast: ne);
      }
    }
    return null;
  }

  /// 序列化 [西南角, 东北角]。
  Object toJson() => <Object>[southwest.toJson(), northeast.toJson()];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LatLngBounds &&
          other.southwest == southwest &&
          other.northeast == northeast;

  @override
  int get hashCode => Object.hash(southwest, northeast);

  @override
  String toString() =>
      'LatLngBounds(southwest: $southwest, northeast: $northeast)';
}
