import 'package:flutter_test/flutter_test.dart';

import 'package:amap_maps_flutter_qs/amap_maps_flutter_qs.dart';

void main() {
  group('AMapUtil', () {
    test('北京到上海球面距离约 1068km', () {
      const beijing = LatLng(39.909187, 116.397451);
      const shanghai = LatLng(31.230416, 121.473701);

      final distance = AMapUtil.distanceBetween(beijing, shanghai);

      expect(distance, closeTo(1068000, 10000));
    });

    test('同点距离为 0', () {
      const point = LatLng(39.9, 116.4);
      expect(AMapUtil.distanceBetween(point, point), 0);
    });

    test('点到区域的距离：区域内为 0，区域外为最近点距离', () {
      const bounds = LatLngBounds(
        southwest: LatLng(39.9, 116.3),
        northeast: LatLng(39.95, 116.4),
      );

      expect(AMapUtil.distanceToBounds(const LatLng(39.92, 116.35), bounds), 0);
      // 纬度超出北界 0.01 度 ≈ 1111m
      final outside = AMapUtil.distanceToBounds(
        const LatLng(39.96, 116.35),
        bounds,
      );
      expect(outside, closeTo(1111, 15));
    });
  });
}
