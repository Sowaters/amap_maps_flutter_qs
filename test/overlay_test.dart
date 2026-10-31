import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';

import 'package:amap_maps_flutter_qs/amap_maps_flutter_qs.dart';

void main() {
  group('覆盖物模型', () {
    test('Marker copyWith 与序列化', () {
      final marker = Marker(id: 'm1', position: const LatLng(1, 2));
      final moved = marker.copyWith(positionParam: const LatLng(3, 4));

      expect(moved.id, 'm1');
      expect(moved.position, const LatLng(3, 4));
      expect(moved.alpha, marker.alpha);

      final json = moved.toJson();
      expect(json['id'], 'm1');
      expect(json['position'], <double>[3, 4]);
    });

    test('Marker 不传 id 自动生成且唯一', () {
      final a = Marker(position: const LatLng(1, 2));
      final b = Marker(position: const LatLng(3, 4));
      expect(a.id, isNotEmpty);
      expect(b.id, isNot(a.id));
      // copyWith 沿用原 id
      expect(a.copyWith().id, a.id);
    });

    test('Marker 官方字段默认值', () {
      final marker = Marker(position: const LatLng(0, 0));
      expect(marker.icon, BitmapDescriptor.defaultMarker);
      expect(marker.alpha, 1.0);
      expect(marker.clickable, isTrue);
      expect(marker.draggable, isFalse);
      expect(marker.flat, isFalse);
    });

    test('BitmapDescriptor 值相等（bytes 重建实例不再触发整批更新）', () {
      Uint8List png() => Uint8List.fromList([1, 2, 3, 4]);

      // 不同实例、相同字节 → 相等（setState 重建场景）
      final a = BitmapDescriptor.fromBytes(png());
      final b = BitmapDescriptor.fromBytes(png());
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);

      // 字节不同 → 不等
      final c = BitmapDescriptor.fromBytes(Uint8List.fromList([1, 2, 3, 5]));
      expect(a == c, isFalse);

      // 相同路径不同实例 → 相等
      expect(
        BitmapDescriptor.fromIconPath('assets/x.png'),
        BitmapDescriptor.fromIconPath('assets/x.png'),
      );

      // 相同实例 identical 短路
      expect(a == a, isTrue);
      expect(BitmapDescriptor.defaultMarker == BitmapDescriptor.defaultMarker,
          isTrue);

      // Marker 携带重建的 bytes 图标 → 差量 diff 应判定无更新
      final m1 = Marker(id: 'm', position: const LatLng(1, 1), icon: a);
      final m2 = Marker(id: 'm', position: const LatLng(1, 1), icon: b);
      expect(m1 == m2, isTrue);
      expect(MarkerUpdates.from({m1}, {m2}).isEmpty, isTrue);
    });

    test('Polyline 序列化与相等性（点集参与 hashCode）', () {
      final a = Polyline(id: 'p1', points: const [LatLng(1, 2), LatLng(3, 4)]);
      final b = a.copyWith();

      expect(a == b, isTrue);

      final json = a.toJson();
      expect(json['points'], [
        <double>[1, 2],
        <double>[3, 4],
      ]);
      expect(json['width'], 10.0);
    });

    test('Polyline geodesic / customTexture 序列化', () {
      final line = Polyline(
        id: 'geo',
        points: const [LatLng(1, 2), LatLng(3, 4)],
        geodesic: true,
        customTexture: BitmapDescriptor.fromIconPath('assets/tex.png'),
      );
      final json = line.toJson();
      expect(json['geodesic'], isTrue);
      expect(
        (json['customTexture'] as Map)['type'],
        'asset',
      );
    });

    test('Circle（基线插件缺失项）序列化', () {
      final circle = Circle(id: 'c1', center: const LatLng(5, 6), radius: 1000);
      final json = circle.toJson();

      expect(json['center'], <double>[5, 6]);
      expect(json['radius'], 1000.0);
    });

    test('Polygon 官方默认值与 joinType 序列化', () {
      final polygon = Polygon(
        id: 'g',
        points: const [LatLng(0, 0), LatLng(1, 1), LatLng(0, 1)],
      );
      expect(polygon.strokeWidth, 10.0);
      expect(polygon.strokeColor, const Color(0xCC00BFFF));
      expect(polygon.fillColor, const Color(0xC487CEFA));
      expect(polygon.joinType, JoinType.bevel);
      expect(polygon.toJson()['joinType'], 'bevel');
    });

    test('sealed MapObject 穷尽匹配', () {
      String describe(MapObject object) => switch (object) {
        Marker() => 'marker',
        Polyline() => 'polyline',
        Polygon() => 'polygon',
        Circle() => 'circle',
      };

      expect(describe(Marker(id: 'm', position: const LatLng(0, 0))), 'marker');
      expect(
        describe(Polyline(id: 'l', points: [const LatLng(0, 0), const LatLng(1, 1)])),
        'polyline',
      );
      expect(
        describe(Polygon(id: 'g', points: [const LatLng(0, 0), const LatLng(1, 1)])),
        'polygon',
      );
      expect(
        describe(Circle(id: 'c', center: const LatLng(0, 0), radius: 1)),
        'circle',
      );
    });
  });

  group('BitmapDescriptor', () {
    test('defaultMarker 与 hue 工厂', () {
      expect(BitmapDescriptor.defaultMarker.toJson()['type'], 'defaultMarker');
      final orange = BitmapDescriptor.defaultMarkerWithHue(
        BitmapDescriptor.hueOrange,
      );
      expect(orange.toJson()['type'], 'defaultMarkerWithHue');
      expect(orange.toJson()['hue'], 30.0);
    });

    test('fromIconPath / fromBytes', () {
      expect(
        BitmapDescriptor.fromIconPath('assets/a.png').toJson()['asset'],
        'assets/a.png',
      );
      expect(
        BitmapDescriptor.fromBytes(Uint8List(4)).toJson()['type'],
        'bytes',
      );
    });

    test('色相常量齐全', () {
      expect(BitmapDescriptor.hueRed, 0.0);
      expect(BitmapDescriptor.hueRose, 330.0);
    });
  });

  group('CameraUpdate', () {
    test('zoomIn / zoomOut 工厂', () {
      expect(CameraUpdate.zoomIn().toJson(), {'op': 'zoomIn'});
      expect(CameraUpdate.zoomOut().toJson(), {'op': 'zoomOut'});
    });
  });
}
