import 'package:flutter_test/flutter_test.dart';

import 'package:amap_maps_flutter_qs/amap_maps_flutter_qs.dart';

void main() {
  group('LatLng', () {
    test('toJson / fromJson 往返一致', () {
      const latLng = LatLng(39.909187, 116.397451);
      final restored = LatLng.fromJson(latLng.toJson());

      expect(restored, latLng);
    });

    test('fromJson 非法输入返回 null', () {
      expect(LatLng.fromJson(null), isNull);
      expect(LatLng.fromJson(<dynamic>[39.9]), isNull);
      expect(LatLng.fromJson('bad'), isNull);
    });

    test('非法坐标触发断言', () {
      expect(() => LatLng(91, 0), throwsA(isA<AssertionError>()));
      expect(() => LatLng(0, 181), throwsA(isA<AssertionError>()));
    });

    test('相等性与 hashCode', () {
      const a = LatLng(1.5, 2.5);
      const b = LatLng(1.5, 2.5);
      const c = LatLng(1.5, 2.6);

      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });
  });

  group('LatLngBounds', () {
    const sw = LatLng(39.9, 116.3);
    const ne = LatLng(39.95, 116.4);
    const bounds = LatLngBounds(southwest: sw, northeast: ne);

    test('center 中心点计算', () {
      expect(bounds.center, const LatLng(39.925, 116.35));
    });

    test('contains 包含判断', () {
      expect(bounds.contains(const LatLng(39.92, 116.35)), isTrue);
      expect(bounds.contains(const LatLng(40.0, 116.35)), isFalse);
    });

    test('toJson / fromJson 往返一致', () {
      final restored = LatLngBounds.fromJson(bounds.toJson());
      expect(restored, bounds);
    });
  });
}
