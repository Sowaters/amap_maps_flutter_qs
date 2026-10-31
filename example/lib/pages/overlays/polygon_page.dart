import 'package:flutter/material.dart';

import 'package:amap_maps_flutter_qs/amap_maps_flutter_qs.dart';

import '../../demo_config.dart';
import 'common.dart';

/// Polygon：样式差量更新与孔洞/镂空结构。
///
/// 本页演示：
/// - strokeColor / fillColor / strokeWidth 运行时切换
/// - hollow 镂空（仅描边不填充，本插件扩展）
/// - holes 孔洞环（本插件扩展，典型来源 GeometryUtil 几何运算）
/// - Polygon.onTap 对象级点击回调
/// - joinType 仅初始化时设置一次（copyWith 不支持修改，与官方一致）
class PolygonPage extends StatefulWidget {
  const PolygonPage({super.key});

  @override
  State<PolygonPage> createState() => _PolygonPageState();
}

class _PolygonPageState extends State<PolygonPage> {
  /// 中间的矩形孔洞（在 district 多边形内部挖空）。
  static const _hole = <LatLng>[
    LatLng(39.9320, 116.4000),
    LatLng(39.9320, 116.4180),
    LatLng(39.9220, 116.4180),
    LatLng(39.9220, 116.4000),
  ];

  static const _fillGreen = Color(0x334CAF50);
  static const _strokeGreen = Color(0xFF4CAF50);
  static const _fillOrange = Color(0x33FF9800);
  static const _strokeOrange = Color(0xFFFF9800);

  String _lastEvent = '试试：点击多边形（对象级 onTap 回调）';

  // late：onTap 闭包引用了 setState，延迟到首次访问时初始化
  late Set<Polygon> _polygons = <Polygon>{
    Polygon(
      id: 'district',
      points: const [
        LatLng(39.9400, 116.3900),
        LatLng(39.9400, 116.4200),
        LatLng(39.9200, 116.4300),
        LatLng(39.9150, 116.4000),
      ],
      strokeColor: _strokeGreen,
      fillColor: _fillGreen,
      strokeWidth: 4,
      onTap: (id) => setState(() => _lastEvent = 'Polygon.onTap（对象级）：$id'),
    ),
  };

  /// 对 district 做差量属性更新并记录事件。
  void _update(Polygon Function(Polygon p) transform, String event) {
    setState(() {
      _polygons = _polygons
          .map((p) => p.id == 'district' ? transform(p) : p)
          .toSet();
      _lastEvent = event;
    });
  }

  /// 换色：填充色 ↔ 描边色同步切换（差量更新）。
  void _toggleColor() {
    _update((p) {
      final green = p.fillColor == _fillGreen;
      return p.copyWith(
        fillColorParam: green ? _fillOrange : _fillGreen,
        strokeColorParam: green ? _strokeOrange : _strokeGreen,
      );
    }, '差量更新多边形（换色）');
  }

  /// 镂空：仅描边，不填充。
  void _toggleHollow() {
    _update((p) {
      final next = !p.hollow;
      return p.copyWith(hollowParam: next);
    }, 'hollow 已切换（镂空后 fillColor 失效，再点恢复）');
  }

  /// 孔洞切换：中间挖一个矩形洞（holes 为本插件扩展）。
  void _toggleHole() {
    _update((p) {
      final hasHole = p.holes.isNotEmpty;
      return p.copyWith(holesParam: hasHole ? const [] : [_hole]);
    }, 'holes 已切换（挖孔/填孔）');
  }

  void _widenStroke(double delta) {
    _update(
      (p) => p.copyWith(
        strokeWidthParam: (p.strokeWidth + delta).clamp(1, 30).toDouble(),
      ),
      'strokeWidth 已切换（±$delta）',
    );
  }

  @override
  Widget build(BuildContext context) {
    return OverlayDemoScaffold(
      title: 'Polygon 面覆盖物',
      event: _lastEvent,
      map: AMapWidget(
        initialCameraPosition: initialCamera,
        polygons: _polygons,
      ),
      groups: [
        OverlayActionGroup('样式差量更新', [
          OverlayAction(Icons.format_color_fill, '换色', _toggleColor),
          OverlayAction(Icons.crop_square, '镂空 hollow', _toggleHollow),
          OverlayAction(Icons.add_box, '挖/填孔洞', _toggleHole),
          OverlayAction(Icons.add, '边框 +', () => _widenStroke(4)),
          OverlayAction(Icons.remove, '边框 -', () => _widenStroke(-4)),
        ]),
      ],
    );
  }
}
