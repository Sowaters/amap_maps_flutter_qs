import 'package:flutter/material.dart';

import 'overlays/circle_page.dart';
import 'overlays/marker_basic_page.dart';
import 'overlays/marker_props_page.dart';
import 'overlays/polyline_page.dart';
import 'overlays/polygon_page.dart';
import 'overlays/track_page.dart';

/// 覆盖物管理：细分 demo 入口（hub 页）。
///
/// 覆盖物体系按类型拆成 5 个子页面，各自聚焦一个主题；
/// 所有增删改都通过 setState 修改 Set 集合，插件内部 diff 后
/// 仅下发变更部分（MarkerUpdates 模式，PRD US-03）。
class OverlaysPage extends StatelessWidget {
  const OverlaysPage({super.key});

  static const _entries = <(IconData, String, String, WidgetBuilder)>[
    (
      Icons.location_pin,
      'Marker 增删改 · 图标工厂',
      '差量新增/删除/更新/清空；fromBytes / fromAssetImage / fromIconPath / '
          'defaultMarkerWithHue 四种图标工厂；拖拽位置同步',
      _buildMarkerBasic,
    ),
    (
      Icons.tune,
      'Marker 属性 · 气泡控制',
      'anchor / flat / visible / zIndex / rotation / alpha / draggable / '
          'infoWindowEnable；InfoWindow.show 自动弹出；showInfoWindow 程序化控制；两级回调',
      _buildMarkerProps,
    ),
    (
      Icons.timeline,
      'Polyline 线覆盖物',
      '顶点延长、geodesic 大地曲线、纹理线、箭头纹理线、虚线/cap/join/'
          '宽度/透明度循环、平滑曲线、对象级 onTap',
      _buildPolyline,
    ),
    (
      Icons.route,
      'GPS 轨迹 · 平滑曲线',
      '真实 GPS 采样点（东莞，65 点）用 Polyline.smooth 渲染为平滑曲线；'
          '平滑密度调节、WGS-84→GCJ-02 纠偏开关、视角适配',
      _buildTrack,
    ),
    (
      Icons.format_shapes,
      'Polygon 面覆盖物',
      '换色、镂空 hollow、孔洞 holes（本插件扩展）、边框宽度、对象级 onTap',
      _buildPolygon,
    ),
    (
      Icons.radio_button_unchecked,
      'Circle 圆覆盖物',
      '半径伸缩、圆心移动、填充/描边换色、边框宽度、对象级 onTap',
      _buildCircle,
    ),
  ];

  static Widget _buildMarkerBasic(BuildContext context) => const MarkerBasicPage();
  static Widget _buildMarkerProps(BuildContext context) => const MarkerPropsPage();
  static Widget _buildPolyline(BuildContext context) => const PolylinePage();
  static Widget _buildTrack(BuildContext context) => const TrackPage();
  static Widget _buildPolygon(BuildContext context) => const PolygonPage();
  static Widget _buildCircle(BuildContext context) => const CirclePage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('覆盖物管理')),
      body: ListView.separated(
        itemCount: _entries.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final (icon, title, description, builder) = _entries[index];
          return ListTile(
            leading: Icon(
              icon,
              size: 28,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: Text(title),
            subtitle: Text(description),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: builder),
            ),
          );
        },
      ),
    );
  }
}
