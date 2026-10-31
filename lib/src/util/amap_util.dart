import 'dart:math' as math;

import '../model/latlng.dart';
import '../model/latlng_bounds.dart';

/// 坐标与几何计算工具（GCJ-02）。
abstract final class AMapUtil {
  /// 地球半径（米），与高德 SDK 保持一致。
  static const double earthRadius = 6378137.0;

  /// 两点间球面距离（米），haversine 公式。
  static double distanceBetween(LatLng from, LatLng to) {
    final lat1 = from.latitude * _degToRad;
    final lat2 = to.latitude * _degToRad;
    final dLat = (to.latitude - from.latitude) * _degToRad;
    final dLng = (to.longitude - from.longitude) * _degToRad;

    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  /// 点到 [bounds] 的最短距离（米）。点在区域内时返回 0。
  static double distanceToBounds(LatLng point, LatLngBounds bounds) {
    if (bounds.contains(point)) return 0;
    final nearest = LatLng(
      point.latitude.clamp(
        bounds.southwest.latitude,
        bounds.northeast.latitude,
      ),
      point.longitude.clamp(
        bounds.southwest.longitude,
        bounds.northeast.longitude,
      ),
    );
    return distanceBetween(point, nearest);
  }

  static const double _degToRad = math.pi / 180.0;
}
