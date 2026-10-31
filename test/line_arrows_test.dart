import 'package:flutter_test/flutter_test.dart';

import 'package:amap_maps_flutter_qs/amap_maps_flutter_qs.dart';

void main() {
  group('AMapUtil.bearingBetween', () {
    const center = LatLng(39.9, 116.4);

    test('正东 ≈ 90°，正西 ≈ 270°，正南 = 180°', () {
      // 沿纬线正东的初始大圆方位角略小于 90°（球面收敛效应）
      expect(AMapUtil.bearingBetween(center, const LatLng(39.9, 116.5)),
          closeTo(90, 0.1));
      expect(AMapUtil.bearingBetween(center, const LatLng(39.9, 116.3)),
          closeTo(270, 0.1));
      expect(AMapUtil.bearingBetween(center, const LatLng(39.8, 116.4)),
          closeTo(180, 0.1));
    });

    test('正北 = 0°（不是 360）', () {
      final bearing = AMapUtil.bearingBetween(center, const LatLng(40.0, 116.4));
      expect(bearing, closeTo(0, 0.01));
      expect(bearing, greaterThanOrEqualTo(0));
      expect(bearing, lessThan(360));
    });

    test('东北在 0° ~ 90° 之间', () {
      final bearing = AMapUtil.bearingBetween(
        center,
        const LatLng(39.95, 116.45),
      );
      expect(bearing, greaterThan(0));
      expect(bearing, lessThan(90));
    });

    test('同点方向未定义但不产生 NaN（约定为 0）', () {
      final bearing = AMapUtil.bearingBetween(center, center);
      expect(bearing.isNaN, isFalse);
    });
  });

  group('LineArrows.alongLine', () {
    // 由南向北 1000m 直线（纬度 1° ≈ 111320m）
    const northLine = [LatLng(39.9000, 116.4), LatLng(39.9090, 116.4)];
    final icon = BitmapDescriptor.defaultMarker;

    test('少于 2 个点返回空', () {
      expect(LineArrows.alongLine(points: const [], icon: icon), isEmpty);
      expect(
        LineArrows.alongLine(points: const [LatLng(39.9, 116.4)], icon: icon),
        isEmpty,
      );
    });

    test('按间距等距生成：1000m 线、300m 间距、默认半间距起步 → 3 个箭头', () {
      final arrows = LineArrows.alongLine(
        points: northLine,
        icon: icon,
        intervalMeters: 300,
      );
      // 位置在 150 / 450 / 750m 处，均 < 1000m
      expect(arrows, hasLength(3));
    });

    test('箭头位置沿线且经度不变（南北向直线）', () {
      final arrows = LineArrows.alongLine(
        points: northLine,
        icon: icon,
        intervalMeters: 300,
      );
      for (final m in arrows) {
        expect(m.position.longitude, closeTo(116.4, 1e-9));
        expect(m.position.latitude, greaterThan(39.9000));
        expect(m.position.latitude, lessThan(39.9090));
      }
      // 依次向北
      expect(arrows[0].position.latitude, lessThan(arrows[1].position.latitude));
      expect(arrows[1].position.latitude, lessThan(arrows[2].position.latitude));
    });

    test('正北方向 rotation = 0，正东方向 rotation = 270（高德逆时针约定）', () {
      final north = LineArrows.alongLine(
        points: northLine,
        icon: icon,
        intervalMeters: 300,
      );
      expect(north.first.rotation, closeTo(0, 1e-9));

      const eastLine = [LatLng(39.9, 116.40), LatLng(39.9, 116.41)];
      final east = LineArrows.alongLine(
        points: eastLine,
        icon: icon,
        intervalMeters: 300,
      );
      expect(east.first.rotation, closeTo(270, 0.01));
    });

    test('id 序列稳定：<idPrefix>_0、_1、_2…（差量更新可正确增删）', () {
      final arrows = LineArrows.alongLine(
        points: northLine,
        icon: icon,
        intervalMeters: 300,
        idPrefix: 'route-arrow',
      );
      expect(arrows.map((m) => m.id).toList(), [
        'route-arrow_0',
        'route-arrow_1',
        'route-arrow_2',
      ]);
    });

    test('间距过小自动截断到 10m，避免生成海量 Marker', () {
      final arrows = LineArrows.alongLine(
        points: northLine,
        icon: icon,
        intervalMeters: 0.001,
      );
      // 1000m / 10m → 100 个以内（起点偏移半个间距）
      expect(arrows.length, lessThanOrEqualTo(100));
      expect(arrows, isNotEmpty);
    });

    test('重合点（退化段）被跳过且不产生 NaN', () {
      final arrows = LineArrows.alongLine(
        points: const [
          LatLng(39.9, 116.4),
          LatLng(39.9, 116.4), // 重合
          LatLng(39.9090, 116.4),
        ],
        icon: icon,
        intervalMeters: 300,
      );
      for (final m in arrows) {
        expect(m.position.latitude.isNaN, isFalse);
        expect(m.rotation.isNaN, isFalse);
      }
      expect(arrows, hasLength(3));
    });

    test('折线转弯处箭头方向跟随所在线段', () {
      // 东 800m 后向北 800m 的 L 形线
      const lShape = [LatLng(39.9000, 116.40), LatLng(39.9000, 116.4094), LatLng(39.9094, 116.4094)];
      final arrows = LineArrows.alongLine(
        points: lShape,
        icon: icon,
        intervalMeters: 400,
      );
      expect(arrows.length, greaterThanOrEqualTo(3));
      // 前段箭头朝东（rotation 270），跨过转弯点后的箭头朝北（rotation 0）
      final first = arrows.first;
      final last = arrows.last;
      expect(first.rotation, closeTo(270, 5));
      expect(last.rotation, closeTo(0, 5));
    });

    test('flat / alpha / zIndex / anchor 透传', () {
      final arrows = LineArrows.alongLine(
        points: northLine,
        icon: icon,
        intervalMeters: 300,
        flat: true,
        alpha: 0.5,
        zIndex: 7,
      );
      final m = arrows.first;
      expect(m.flat, isTrue);
      expect(m.alpha, 0.5);
      expect(m.zIndex, 7);
      expect(m.anchor, const Offset(0.5, 0.5));
    });
  });
}
