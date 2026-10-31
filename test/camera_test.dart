import 'package:flutter_test/flutter_test.dart';

import 'package:amap_maps_flutter_qs/amap_maps_flutter_qs.dart';

void main() {
  group('CameraUpdate 序列化', () {
    test('newLatLng', () {
      final json =
          CameraUpdate.newLatLng(const LatLng(1, 2)).toJson()
              as Map<String, Object?>;

      expect(json['op'], 'newLatLng');
      expect(json['latLng'], <double>[1, 2]);
    });

    test('newLatLngZoom', () {
      final json =
          CameraUpdate.newLatLngZoom(const LatLng(1, 2), 13.5).toJson()
              as Map<String, Object?>;

      expect(json['op'], 'newLatLngZoom');
      expect(json['zoom'], 13.5);
    });

    test('newLatLngBounds', () {
      final json =
          CameraUpdate.newLatLngBounds(
                const LatLngBounds(
                  southwest: LatLng(1, 2),
                  northeast: LatLng(3, 4),
                ),
                64.0,
              ).toJson()
              as Map<String, Object?>;

      expect(json['op'], 'newLatLngBounds');
      expect(json['padding'], 64.0);
      expect(json['bounds'], <List<double>>[
        <double>[1, 2],
        <double>[3, 4],
      ]);
    });

    test('newCameraPosition', () {
      final json =
          CameraUpdate.newCameraPosition(
                const CameraPosition(
                  target: LatLng(5, 6),
                  zoom: 12,
                  bearing: 90,
                ),
              ).toJson()
              as Map<String, Object?>;

      expect(json['op'], 'newCameraPosition');
      final camera = json['cameraPosition']! as Map<String, Object?>;
      expect(camera['zoom'], 12.0);
      expect(camera['bearing'], 90.0);
    });

    test('zoomTo / zoomBy / scrollBy', () {
      expect((CameraUpdate.zoomTo(15).toJson() as Map)['op'], 'zoomTo');
      expect((CameraUpdate.zoomBy(-1.5).toJson() as Map)['amount'], -1.5);
      final scroll = CameraUpdate.scrollBy(10, 20).toJson() as Map;
      expect(scroll['dx'], 10.0);
      expect(scroll['dy'], 20.0);
    });
  });

  group('CameraPosition / MapType', () {
    test('CameraPosition 序列化往返', () {
      const position = CameraPosition(
        target: LatLng(39.9, 116.4),
        zoom: 11,
        tilt: 30,
        bearing: 45,
      );
      final restored = CameraPosition.fromJson(position.toJson());

      expect(restored, position);
    });

    test('MapType 原生编码对照', () {
      expect(MapType.normal.nativeCode, 1);
      expect(MapType.satellite.nativeCode, 2);
      expect(MapType.night.nativeCode, 3);

      expect(MapType.fromJson(2), MapType.satellite);
      expect(MapType.fromJson(999), MapType.normal);
    });
  });
}
