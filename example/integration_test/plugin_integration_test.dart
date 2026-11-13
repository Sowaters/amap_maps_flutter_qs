// 集成测试：在真实设备/模拟器上验证插件基础链路。
//
// 运行：
//   flutter test integration_test/plugin_integration_test.dart \
//     -d <android-or-ios-device-id>
//
// 注意：需要先在 example/lib/main.dart 中配置真实的高德 Key。

import 'dart:async';

import 'package:amap_maps_flutter_qs/amap_maps_flutter_qs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:amap_maps_flutter_qs_example/demo_config.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('地图创建与原生相机控制', (WidgetTester tester) async {
    await AMapInitializer.init(
      apiKey: demoApiKey,
      privacyStatement: demoPrivacy,
    );
    final controllerCompleter = Completer<AMapController>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AMapWidget(
            initialCameraPosition: const CameraPosition(
              target: LatLng(39.909187, 116.397451),
              zoom: 10,
            ),
            onMapCreated: controllerCompleter.complete,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AMapWidget), findsOneWidget);
    final controller = await controllerCompleter.future.timeout(
      const Duration(seconds: 30),
    );
    const target = LatLng(31.230416, 121.473701);
    await controller.moveCamera(
      CameraUpdate.newLatLngZoom(target, 8),
      animated: false,
    );
    final cameraPosition = await controller.getCameraPosition();

    expect(cameraPosition.target.latitude, closeTo(target.latitude, 0.01));
    expect(cameraPosition.target.longitude, closeTo(target.longitude, 0.01));
    expect(cameraPosition.zoom, closeTo(8, 0.5));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
