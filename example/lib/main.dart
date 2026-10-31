import 'package:flutter/material.dart';

import 'package:amap_maps_flutter_qs/amap_maps_flutter_qs.dart';

import 'demo_config.dart';
import 'pages/camera_page.dart';
import 'pages/custom_bubble_page.dart';
import 'pages/custom_style_page.dart';
import 'pages/events_page.dart';
import 'pages/geometry_page.dart';
import 'pages/map_types_page.dart';
import 'pages/marker_stress_page.dart';
import 'pages/my_location_page.dart';
import 'pages/overlays_page.dart';
import 'pages/snapshot_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AMapInitializer.init(apiKey: demoApiKey, privacyStatement: demoPrivacy);
  runApp(const DemoApp());
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'amap_maps_flutter_qs demo',
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
      home: const DemoHomePage(),
    );
  }
}

class _DemoEntry {
  final IconData icon;
  final String title;
  final String description;
  final WidgetBuilder page;

  const _DemoEntry(this.icon, this.title, this.description, this.page);
}

final _entries = <_DemoEntry>[
  _DemoEntry(
    Icons.map_outlined,
    '地图配置（动态更新）',
    'MapType / 手势 / 路况、建筑、标注、指南针、比例尺 / limitBounds 全部运行时切换',
    (_) => const MapTypesPage(),
  ),
  _DemoEntry(
    Icons.location_pin,
    '覆盖物管理',
    'Marker 增删改（差量更新）、图标工厂（bytes/asset/hue）、anchor/flat/visible/zIndex、'
        'showInfoWindow；Polyline geodesic / 纹理线 / 虚线样式',
    (_) => const OverlaysPage(),
  ),
  _DemoEntry(
    Icons.control_camera,
    '相机控制',
    'CameraUpdate 全部工厂（含 zoomByFocus）、moveCamera / animateCamera、实时相机状态',
    (_) => const CameraPage(),
  ),
  _DemoEntry(
    Icons.highlight_alt,
    '几何运算 · 不相交区域',
    'GeometryUtil XOR：两圆月牙形、两多边形 L 形、同心圆环形（含孔洞）',
    (_) => const GeometryPage(),
  ),
  _DemoEntry(
    Icons.touch_app,
    '地图事件',
    '地图点击/长按、POI 点击、Marker 点击/拖拽、相机移动回调的事件日志 + 距离测量',
    (_) => const EventsPage(),
  ),
  _DemoEntry(
    Icons.my_location,
    '定位蓝点',
    'MyLocationStyleOptions：五种定位模式切换、精度圈颜色',
    (_) => const MyLocationPage(),
  ),
  _DemoEntry(
    Icons.bubble_chart_outlined,
    'Marker 压力测试',
    '200 / 500 / 1000 / 2000 个 Marker 全量替换的差量更新耗时与真机渲染',
    (_) => const MarkerStressPage(),
  ),
  _DemoEntry(
    Icons.dashboard_customize,
    '自定义气泡',
    'renderWidgetToPng 把 Flutter Widget 截图后赋给 InfoWindow.content',
    (_) => const CustomBubblePage(),
  ),
  _DemoEntry(
    Icons.style,
    '自定义地图样式',
    'CustomStyleOptions 云端样式 ID 模式（仅 Android）',
    (_) => const CustomStylePage(),
  ),
  _DemoEntry(
    Icons.camera_alt_outlined,
    '截图与合规',
    'takeSnapshot 地图截图、审图号查询（上架合规展示）',
    (_) => const SnapshotPage(),
  ),
];

class DemoHomePage extends StatelessWidget {
  const DemoHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('amap_maps_flutter_qs demo')),
      body: ListView.separated(
        itemCount: _entries.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final entry = _entries[index];
          return ListTile(
            leading: Icon(entry.icon, size: 28, color: Theme.of(context).colorScheme.primary),
            title: Text(entry.title),
            subtitle: Text(entry.description),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: entry.page),
            ),
          );
        },
      ),
    );
  }
}

/// Demo 通用小提示条。
void showDemoTip(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(milliseconds: 900),
    ));
}
