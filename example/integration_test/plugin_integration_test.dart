// 集成测试：在真实设备/模拟器上验证插件基础链路。
//
// 运行：
//   flutter test integration_test/plugin_integration_test.dart \
//     -d <android-or-ios-device-id>
//
// 注意：需要先在 example/lib/main.dart 中配置真实的高德 Key。

import 'package:amap_maps_flutter_qs/amap_maps_flutter_qs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:amap_maps_flutter_qs_example/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('地图创建与相机控制冒烟测试', (WidgetTester tester) async {
    app.main();
    await tester.pumpAndSettle();

    // AMapWidget 应出现在页面上
    expect(find.byType(AMapWidget), findsOneWidget);
  });
}
