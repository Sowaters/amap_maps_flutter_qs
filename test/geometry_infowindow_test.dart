import 'dart:typed_data';

import 'package:amap_maps_flutter_qs/amap_maps_flutter_qs.dart';
import 'package:flutter_test/flutter_test.dart';

const _centerA = LatLng(39.909, 116.397);
const _centerB = LatLng(39.909, 116.42); // 向东约 1.96 km

void main() {
  group('GeometryUtil', () {
    test('circleToPoints 生成正确段数且半径误差可接受', () {
      final ring = GeometryUtil.circleToPoints(_centerA, 1000);
      expect(ring.length, 96);
      for (final p in ring) {
        expect(AMapUtil.distanceBetween(_centerA, p), closeTo(1000, 20));
      }
    });

    test('两圆相交时 XOR 返回月牙形区域', () {
      final a = Circle(id: 'a', center: _centerA, radius: 1500);
      final b = Circle(id: 'b', center: _centerB, radius: 1500);
      final result = GeometryUtil.xorCircles(a, b);
      expect(result, isNotEmpty);
      for (final p in result) {
        expect(p.points.length, greaterThanOrEqualTo(3));
        expect(p.id, startsWith('xor'));
      }
    });

    test('两圆分离时 XOR 为两个完整圆', () {
      final a = Circle(id: 'a', center: _centerA, radius: 500);
      final b = Circle(id: 'b', center: const LatLng(40.1, 116.8), radius: 500);
      final result = GeometryUtil.xorCircles(a, b);
      expect(result.length, 2);
    });

    test('圆包含圆时 XOR 为带孔环形，孔半径约等于内圆', () {
      final a = Circle(id: 'a', center: _centerA, radius: 3000);
      final b = Circle(id: 'b', center: _centerA, radius: 1000);
      final result = GeometryUtil.xorCircles(a, b);
      expect(result.length, 1);
      expect(result.first.holes.length, 1);
      final holePoint = result.first.holes.first.first;
      expect(
        AMapUtil.distanceBetween(_centerA, holePoint),
        closeTo(1000, 30),
      );
    });

    test('两正方形相交时 XOR 为两块 L 形（无孔洞）', () {
      final a = Polygon(
        id: 'pa',
        points: const [
          LatLng(39.90, 116.39),
          LatLng(39.92, 116.39),
          LatLng(39.92, 116.41),
          LatLng(39.90, 116.41),
        ],
      );
      final b = Polygon(
        id: 'pb',
        points: const [
          LatLng(39.91, 116.40),
          LatLng(39.93, 116.40),
          LatLng(39.93, 116.42),
          LatLng(39.91, 116.42),
        ],
      );
      final result = GeometryUtil.xorPolygons(a, b);
      expect(result.length, 2);
      for (final p in result) {
        expect(p.holes, isEmpty);
      }
    });

    test('两多边形完全重合时 XOR 返回空', () {
      final ring = const [
        LatLng(39.90, 116.39),
        LatLng(39.92, 116.39),
        LatLng(39.92, 116.41),
        LatLng(39.90, 116.41),
      ];
      final result = GeometryUtil.xorPolygons(
        Polygon(id: 'a', points: ring),
        Polygon(id: 'b', points: ring),
      );
      expect(result, isEmpty);
    });

    test('多边形内含时 XOR 为带孔环形', () {
      final outer = const [
        LatLng(39.90, 116.39),
        LatLng(39.94, 116.39),
        LatLng(39.94, 116.43),
        LatLng(39.90, 116.43),
      ];
      final inner = const [
        LatLng(39.91, 116.40),
        LatLng(39.93, 116.40),
        LatLng(39.93, 116.42),
        LatLng(39.91, 116.42),
      ];
      final result = GeometryUtil.xorPolygons(
        Polygon(id: 'a', points: outer),
        Polygon(id: 'b', points: inner),
      );
      expect(result.length, 1);
      expect(result.first.holes.length, 1);
    });

    test('圆与多边形 XOR 可用', () {
      final circle = Circle(id: 'c', center: _centerA, radius: 800);
      final polygon = Polygon(
        id: 'p',
        points: const [
          LatLng(39.905, 116.393),
          LatLng(39.915, 116.393),
          LatLng(39.915, 116.403),
          LatLng(39.905, 116.403),
        ],
      );
      final result = GeometryUtil.xorCirclePolygon(circle, polygon);
      expect(result, isNotEmpty);
    });
  });

  group('InfoWindow 自定义内容', () {
    test('content 序列化进 toJson', () {
      final window = InfoWindow(
        content: BitmapDescriptor.fromBytes(
          Uint8List.fromList(const [1, 2, 3]),
        ),
      );
      final json = window.toJson();
      expect((json['content'] as Map)['type'], 'bytes');
    });

    test('content 变化触发 Marker diff 更新', () {
      Marker marker(Uint8List bytes) => Marker(
        id: 'm',
        position: _centerA,
        infoWindow: InfoWindow(content: BitmapDescriptor.fromBytes(bytes)),
      );
      final updates = MarkerUpdates.from(
        {marker(Uint8List.fromList(const [1]))},
        {marker(Uint8List.fromList(const [2]))},
      );
      expect(updates.markersToChange.length, 1);
    });

    test('show 字段序列化并参与 diff', () {
      final base = Marker(
        id: 'm',
        position: _centerA,
        infoWindow: const InfoWindow(title: 'a'),
      );
      final shown = base.copyWith(
        infoWindowParam: const InfoWindow(title: 'a', show: true),
      );
      expect(base == shown, isFalse);
      expect(MarkerUpdates.from({base}, {shown}).markersToChange.length, 1);
      expect(shown.infoWindow.toJson()['show'], isTrue);
      expect(base.infoWindow.toJson()['show'], isFalse);
    });
  });

  group('Polygon.holes', () {
    const hole = [
      LatLng(39.91, 116.40),
      LatLng(39.92, 116.40),
      LatLng(39.92, 116.41),
    ];

    test('参与序列化', () {
      final polygon = Polygon(
        id: 'p',
        points: const [
          LatLng(39.90, 116.39),
          LatLng(39.93, 116.39),
          LatLng(39.93, 116.42),
          LatLng(39.90, 116.42),
        ],
        holes: [hole],
      );
      final json = polygon.toJson();
      expect((json['holes'] as List).length, 1);
    });

    test('参与相等性与 diff', () {
      final base = Polygon(
        id: 'p',
        points: const [
          LatLng(39.90, 116.39),
          LatLng(39.93, 116.39),
          LatLng(39.93, 116.42),
          LatLng(39.90, 116.42),
        ],
      );
      final withHole = base.copyWith(holesParam: [hole]);
      expect(base == withHole, isFalse);
      final updates = PolygonUpdates.from({base}, {withHole});
      expect(updates.polygonsToChange.length, 1);
    });
  });
}
