import 'package:flutter/material.dart';

import 'package:amap_maps_flutter_qs/amap_maps_flutter_qs.dart';

import '../../demo_config.dart';
import 'common.dart';

/// Circle：半径/圆心/颜色差量更新。
///
/// 本页演示：
/// - radius 半径伸缩（copyWith radiusParam）
/// - center 圆心移动（copyWith centerParam，圆随之平移）
/// - fillColor / strokeColor / strokeWidth 运行时切换
/// - Circle.onTap 对象级点击回调（Widget 级只有 Marker 有，
///   线/面/圆的点击回调都注册在覆盖物对象上）
class CirclePage extends StatefulWidget {
  const CirclePage({super.key});

  @override
  State<CirclePage> createState() => _CirclePageState();
}

class _CirclePageState extends State<CirclePage> {
  /// 预设圆心（点击「移动圆心」循环切换）。
  static const _centers = [
    LatLng(39.9000, 116.3900),
    beijingCenter, // 天安门
    LatLng(39.9000, 116.4200),
  ];

  static const _fillColors = [
    Color(0x22FF5722),
    Color(0x222196F3),
    Color(0x224CAF50),
  ];
  static const _strokeColors = [
    Color(0xFFFF5722),
    Color(0xFF2196F3),
    Color(0xFF4CAF50),
  ];

  int _centerIndex = 0;
  int _colorIndex = 0;

  String _lastEvent = '试试：点击圆（对象级 onTap 回调）';

  // late：onTap 闭包引用了 setState，延迟到首次访问时初始化
  late Set<Circle> _circles = <Circle>{
    Circle(
      id: 'service-area',
      center: _centers[0],
      radius: 600,
      strokeColor: _strokeColors[0],
      fillColor: _fillColors[0],
      strokeWidth: 4,
      onTap: (id) => setState(() => _lastEvent = 'Circle.onTap（对象级）：$id'),
    ),
  };

  void _update(Circle Function(Circle c) transform, String event) {
    setState(() {
      _circles = _circles
          .map((c) => c.id == 'service-area' ? transform(c) : c)
          .toSet();
      _lastEvent = event;
    });
  }

  void _resize(double delta) {
    _update(
      (c) => c.copyWith(radiusParam: (c.radius + delta).clamp(100, 5000)),
      '差量更新圆：半径 → ${(_circles.first.radius + delta).clamp(100, 5000).round()}m',
    );
  }

  void _moveCenter() {
    _centerIndex = (_centerIndex + 1) % _centers.length;
    _update(
      (c) => c.copyWith(centerParam: _centers[_centerIndex]),
      '圆心移动 → ${_centerIndex == 1 ? '天安门' : '(${_centers[_centerIndex].latitude}, ${_centers[_centerIndex].longitude})'}',
    );
  }

  void _cycleColor() {
    _colorIndex = (_colorIndex + 1) % _fillColors.length;
    _update(
      (c) => c.copyWith(
        fillColorParam: _fillColors[_colorIndex],
        strokeColorParam: _strokeColors[_colorIndex],
      ),
      '换色（填充 + 描边）',
    );
  }

  void _widenStroke(double delta) {
    _update(
      (c) => c.copyWith(
        strokeWidthParam: (c.strokeWidth + delta).clamp(1, 30).toDouble(),
      ),
      'strokeWidth 已切换（±$delta）',
    );
  }

  @override
  Widget build(BuildContext context) {
    return OverlayDemoScaffold(
      title: 'Circle 圆覆盖物',
      event: _lastEvent,
      map: AMapWidget(
        initialCameraPosition: initialCamera,
        circles: _circles,
      ),
      groups: [
        OverlayActionGroup('形状差量更新', [
          OverlayAction(Icons.add_circle_outline, '半径 +500m', () => _resize(500)),
          OverlayAction(Icons.remove_circle_outline, '半径 -500m', () => _resize(-500)),
          OverlayAction(Icons.open_with, '移动圆心', _moveCenter),
        ]),
        OverlayActionGroup('样式差量更新', [
          OverlayAction(Icons.format_color_fill, '换色', _cycleColor),
          OverlayAction(Icons.add, '边框 +', () => _widenStroke(4)),
          OverlayAction(Icons.remove, '边框 -', () => _widenStroke(-4)),
        ]),
      ],
    );
  }
}
