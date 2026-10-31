/// 经纬度坐标对象（单位：度）。
///
/// 坐标系：GCJ-02（国测局坐标，高德 SDK 默认坐标系）。
class LatLng {
  /// 纬度，范围 [-90.0, 90.0]。
  final double latitude;

  /// 经度，范围 [-180.0, 180.0]。
  final double longitude;

  const LatLng(this.latitude, this.longitude)
    : assert(
        latitude >= -90.0 && latitude <= 90.0,
        'latitude must be in [-90, 90], got $latitude',
      ),
      assert(
        longitude >= -180.0 && longitude <= 180.0,
        'longitude must be in [-180, 180], got $longitude',
      );

  /// 从通道消息反序列化。
  static LatLng? fromJson(Object? json) {
    if (json is List && json.length == 2) {
      return LatLng((json[0] as num).toDouble(), (json[1] as num).toDouble());
    }
    return null;
  }

  /// 序列化为紧凑数组，用于平台通道传输。
  Object toJson() => <double>[latitude, longitude];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LatLng &&
          other.latitude == latitude &&
          other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'LatLng($latitude, $longitude)';
}
