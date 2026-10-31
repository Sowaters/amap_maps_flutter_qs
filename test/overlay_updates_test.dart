import 'dart:ui';

import 'package:amap_maps_flutter_qs/src/model/latlng.dart';
import 'package:amap_maps_flutter_qs/src/overlay/overlay.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  LatLng lat(double lat) => LatLng(lat, 116.397451);

  group('MarkerUpdates', () {
    test('无变化时三部分均为空且 isEmpty 为 true', () {
      final markers = {
        Marker(id: 'a', position: lat(39.9)),
        Marker(id: 'b', position: lat(39.8)),
      };
      final updates = MarkerUpdates.from(markers, markers);
      expect(updates.isEmpty, isTrue);
      expect(updates.markersToAdd, isEmpty);
      expect(updates.markersToChange, isEmpty);
      expect(updates.markersToRemove, isEmpty);
    });

    test('新增 / 删除正确归类', () {
      final previous = {Marker(id: 'keep', position: lat(39.9)), Marker(id: 'old', position: lat(39.8))};
      final current = {Marker(id: 'keep', position: const LatLng(39.9, 116.397451)), Marker(id: 'new', position: lat(39.7))};

      final updates = MarkerUpdates.from(previous, current);
      expect(updates.markersToAdd.map((m) => m.id), ['new']);
      expect(updates.markersToRemove.map((m) => m.id), ['old']);
      expect(updates.markersToChange, isEmpty);
    });

    test('同 id 属性变化进入 toChange（回调变化不触发更新）', () {
      final previous = {Marker(id: 'm', position: lat(39.9))};

      // 仅回调变化：不进入 toChange（== 不比较回调）
      final withCallback = Marker(id: 'm', position: lat(39.9), onTap: (_) {});
      expect(MarkerUpdates.from(previous, {withCallback}).isEmpty, isTrue);

      // 位置变化：进入 toChange
      final moved = MarkerUpdates.from(previous, {
        previous.first.copyWith(positionParam: lat(39.95)),
      });
      expect(moved.markersToChange.map((m) => m.id), ['m']);
    });

    test('toJson 通道 payload 形状正确', () {
      final updates = MarkerUpdates.from(
        {Marker(id: 'old', position: lat(39.9))},
        {Marker(id: 'new', position: lat(39.8))},
      );
      final json = updates.toJson();
      expect(json['toAdd'], isA<List<dynamic>>());
      expect((json['toAdd']! as List).single, containsPair('id', 'new'));
      expect((json['toRemove']! as List).single, 'old');
      expect(json['toUpdate'], isEmpty);
    });
  });

  group('PolylineUpdates', () {
    test('顶点变化进入 toChange', () {
      final previous = {
        Polyline(id: 'l', points: [lat(39.9), lat(39.8)]),
      };
      final updates = PolylineUpdates.from(previous, {
        Polyline(id: 'l', points: [lat(39.9), lat(39.85), lat(39.8)]),
      });
      expect(updates.polylinesToChange.map((l) => l.id), ['l']);
      expect(updates.isEmpty, isFalse);
    });

    test('相同顶点不触发更新', () {
      Polyline make() => Polyline(id: 'l', points: [lat(39.9), lat(39.8)]);
      expect(PolylineUpdates.from({make()}, {make()}).isEmpty, isTrue);
    });
  });

  group('PolygonUpdates', () {
    test('填充色变化进入 toChange', () {
      final points = [lat(39.9), lat(39.8), lat(39.85)];
      final updates = PolygonUpdates.from(
        {Polygon(id: 'p', points: points)},
        {Polygon(id: 'p', points: points, fillColor: const Color(0x55FF0000))},
      );
      expect(updates.polygonsToChange.map((p) => p.id), ['p']);
    });
  });

  group('CircleUpdates', () {
    test('半径变化进入 toChange，圆心变化进入 toChange', () {
      final updates = CircleUpdates.from(
        {Circle(id: 'c', center: lat(39.9), radius: 100)},
        {Circle(id: 'c', center: lat(39.9), radius: 200)},
      );
      expect(updates.circlesToChange, hasLength(1));

      final moved = CircleUpdates.from(
        {Circle(id: 'c', center: lat(39.9), radius: 100)},
        {Circle(id: 'c', center: lat(39.91), radius: 100)},
      );
      expect(moved.circlesToChange, hasLength(1));
    });

    test('toJson payload 含 toAdd/toUpdate/toRemove 三键', () {
      final json = CircleUpdates.from(
        {Circle(id: 'c', center: lat(39.9), radius: 100)},
        {Circle(id: 'c2', center: lat(39.9), radius: 100)},
      ).toJson();
      expect(json.keys, containsAll(['toAdd', 'toUpdate', 'toRemove']));
    });
  });
}
