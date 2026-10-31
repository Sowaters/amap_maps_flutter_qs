import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:amap_maps_flutter_qs/src/model/amap_poi.dart';
import 'package:amap_maps_flutter_qs/src/model/camera_target_bounds.dart';
import 'package:amap_maps_flutter_qs/src/model/custom_style_options.dart';
import 'package:amap_maps_flutter_qs/src/model/latlng.dart';
import 'package:amap_maps_flutter_qs/src/model/latlng_bounds.dart';
import 'package:amap_maps_flutter_qs/src/model/min_max_zoom_preference.dart';
import 'package:amap_maps_flutter_qs/src/model/my_location_style_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MinMaxZoomPreference', () {
    test('unbounded 两端均为 null', () {
      expect(MinMaxZoomPreference.unbounded.minZoom, isNull);
      expect(MinMaxZoomPreference.unbounded.maxZoom, isNull);
    });

    test('toJson 保留 null 端', () {
      final json = const MinMaxZoomPreference(3.0, null).toJson();
      expect(json['min'], 3.0);
      expect(json['max'], isNull);
    });

    test('相等性', () {
      expect(
        const MinMaxZoomPreference(3.0, 20.0),
        const MinMaxZoomPreference(3.0, 20.0),
      );
      expect(
        const MinMaxZoomPreference(3.0, 20.0),
        isNot(const MinMaxZoomPreference(3.0, 19.0)),
      );
    });
  });

  group('CameraTargetBounds', () {
    test('unbounded 序列化为 null', () {
      expect(CameraTargetBounds.unbounded.toJson(), isNull);
    });

    test('有界序列化与往返', () {
      const bounds = LatLngBounds(
        southwest: LatLng(39.0, 116.0),
        northeast: LatLng(40.0, 117.0),
      );
      final json = const CameraTargetBounds(bounds).toJson();
      expect(json, bounds.toJson());

      final restored = CameraTargetBounds.fromJson(json);
      expect(restored.bounds, bounds);
    });

    test('fromJson(null) 视为 unbounded', () {
      expect(CameraTargetBounds.fromJson(null).bounds, isNull);
    });
  });

  group('MyLocationStyleOptions', () {
    test('官方构造与序列化', () {
      final json = const MyLocationStyleOptions(true).toJson();
      expect(json['enabled'], isTrue);
      expect(json['locationMode'], 'locate');
      expect(json['icon'], isNull);
      expect(json['circleFillColor'], isNull);
    });

    test('精度圈字段序列化', () {
      const style = MyLocationStyleOptions(
        false,
        circleFillColor: Color(0x55FF0000),
        circleStrokeColor: Color(0xFF00FF00),
        circleStrokeWidth: 2.0,
        locationMode: MyLocationMode.follow,
      );
      final json = style.toJson();
      expect(json['enabled'], isFalse);
      expect(json['circleFillColor'], 0x55FF0000);
      expect(json['circleStrokeColor'], 0xFF00FF00);
      expect(json['circleStrokeWidth'], 2.0);
      expect(json['locationMode'], 'follow');
    });

    test('相等性', () {
      expect(
        const MyLocationStyleOptions(true, locationMode: MyLocationMode.show),
        const MyLocationStyleOptions(true, locationMode: MyLocationMode.show),
      );
    });
  });

  group('CustomStyleOptions', () {
    test('官方本地样式构造', () {
      const options = CustomStyleOptions(true);
      expect(options.enabled, isTrue);
      expect(options.hasStyle, isFalse);
      expect(options.toJson()['enabled'], isTrue);
    });

    test('本地样式数据序列化', () {
      final options = CustomStyleOptions(
        true,
        styleData: Uint8List.fromList([1, 2, 3]),
        styleExtraData: Uint8List.fromList([4]),
      );
      expect(options.hasStyle, isTrue);
      final json = options.toJson();
      expect(json['styleData'], isA<Uint8List>());
      expect(json['styleExtraData'], isA<Uint8List>());
      expect(options, CustomStyleOptions(true, styleData: Uint8List.fromList([1, 2, 3]), styleExtraData: Uint8List.fromList([4])));
    });

    test('云端样式 ID（本插件扩展）', () {
      const options = CustomStyleOptions(true, customStyleId: 'style-001');
      expect(options.hasStyle, isTrue);
      expect(options.toJson()['customStyleId'], 'style-001');
    });
  });

  group('AMapPoi', () {
    test('fromJson 往返', () {
      const poi = AMapPoi(
        id: 'B000A8UIN8',
        name: '天安门',
        position: LatLng(39.909187, 116.397451),
      );
      final restored = AMapPoi.fromJson(poi.toJson())!;
      expect(restored.id, 'B000A8UIN8');
      expect(restored.name, '天安门');
      expect(restored.position, poi.position);
    });

    test('fromJson 缺 name 返回 null', () {
      expect(AMapPoi.fromJson({'id': 'x'}), isNull);
      expect(AMapPoi.fromJson(null), isNull);
    });

    test('position 缺省时不写键', () {
      final json = const AMapPoi(id: '1', name: 'poi').toJson();
      expect(json.containsKey('position'), isFalse);
    });
  });
}
