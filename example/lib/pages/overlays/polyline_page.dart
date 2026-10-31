import 'package:flutter/material.dart';

import 'package:amap_maps_flutter_qs/amap_maps_flutter_qs.dart';

import '../../demo_config.dart';
import 'common.dart';

/// Polyline：差量更新与全部线样式。
///
/// 本页演示：
/// - 延长顶点（pointsParam 差量更新）
/// - geodesic 大地曲线 vs 普通直线（缩远可见弧线）
/// - customTexture 纹理线（设置后 color 失效）
/// - 箭头纹理线：texture_green 自带 V 形箭头，纹理沿线平铺指示方向（Android）
/// - DashLineType 全部虚线类型循环
/// - CapType（butt/round/square/arrow）与 JoinType（bevel/miter/round）循环
/// - width / alpha 运行时切换
/// - Polyline.smooth + LineSmoothing：Catmull-Rom 样条平滑曲线
/// - Polyline.onTap 对象级点击回调
class PolylinePage extends StatefulWidget {
  const PolylinePage({super.key});

  @override
  State<PolylinePage> createState() => _PolylinePageState();
}

class _PolylinePageState extends State<PolylinePage> {
  AMapController? _controller;

  static const _dashTypes = [
    DashLineType.none,
    DashLineType.dash,
    DashLineType.dashDot,
    DashLineType.dot,
  ];
  static const _capTypes = [
    CapType.butt,
    CapType.round,
    CapType.square,
    CapType.arrow,
  ];
  static const _joinTypes = [JoinType.bevel, JoinType.miter, JoinType.round];
  static const _widths = [4.0, 8.0, 16.0, 24.0];
  static const _alphas = [1.0, 0.6, 0.3];

  String _lastEvent = '试试：点击蓝色折线（对象级 onTap 回调）';

  // late：onTap 闭包引用了 setState，延迟到首次访问时初始化
  late Set<Polyline> _polylines = <Polyline>{
    Polyline(
      id: 'route-solid',
      points: const [
        LatLng(39.9200, 116.3800),
        LatLng(39.9100, 116.4000),
        LatLng(39.8950, 116.4100),
      ],
      width: 8,
      color: const Color(0xCC2196F3),
      capType: CapType.round,
      joinType: JoinType.round,
      onTap: (id) => setState(() => _lastEvent = 'Polyline.onTap（对象级）：$id'),
    ),
    Polyline(
      id: 'route-dash',
      points: const [LatLng(39.8800, 116.3800), LatLng(39.8700, 116.4050)],
      width: 6,
      color: const Color(0xCC9C27B0),
      dashLineType: DashLineType.dash,
    ),
  };

  /// 对 route-solid 做差量属性更新。
  void _updateRouteSolid(Polyline Function(Polyline p) transform) {
    setState(() {
      _polylines = _polylines
          .map((p) => p.id == 'route-solid' ? transform(p) : p)
          .toSet();
    });
  }

  void _extendPolyline() {
    _updateRouteSolid((p) {
      final last = p.points.last;
      return p.copyWith(
        pointsParam: [
          ...p.points,
          LatLng(last.latitude - 0.008, last.longitude + 0.006),
        ],
      );
    });
    setState(() => _lastEvent = '差量更新折线（route-solid 延长一段）');
  }

  /// 大地曲线：北京 → 上海（缩远后可见弧线，与直线对比）。
  Future<void> _addGeodesicLine() async {
    const points = [beijingCenter, shanghaiCenter];
    setState(() {
      _polylines = {
        ..._polylines.where((p) => p.id != 'route-geodesic'),
        Polyline(
          id: 'route-geodesic',
          points: points,
          width: 6,
          color: const Color(0xCCFF9800),
          geodesic: true,
        ),
        // 普通直线做对比
        Polyline(
          id: 'route-straight',
          points: points,
          width: 2,
          color: const Color(0x88607D8B),
          geodesic: false,
        ),
      };
      _lastEvent = 'geodesic 大地曲线（橙）vs 直线（灰）';
    });
    await _controller?.moveCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: const LatLng(31.2, 116.3),
          northeast: const LatLng(39.95, 121.5),
        ),
        60,
      ),
    );
  }

  /// 纹理线：customTexture 替代纯色（color 失效）。
  void _addTextureLine() {
    setState(() {
      _polylines = {
        ..._polylines.where((p) => p.id != 'route-texture'),
        Polyline(
          id: 'route-texture',
          points: const [
            LatLng(39.9350, 116.3800),
            LatLng(39.9280, 116.4150),
            LatLng(39.9420, 116.4350),
          ],
          width: 24,
          customTexture: BitmapDescriptor.fromIconPath(
            'assets/texture_line.png',
          ),
        ),
      };
      _lastEvent = 'customTexture 纹理线（设置后 color 失效）';
    });
  }

  /// 箭头纹理线（Android 特性）：texture_green.png 自带白色 V 形箭头，
  /// 纹理沿线重复平铺即形成方向指示 —— 对应 QTexturePolyline 的
  /// drawSymbol + symbolImage 思路，但箭头间距由纹理图尺寸决定，
  /// 无法像 symbolGap 那样按 Point 精确控制。
  /// 注意：设置 customTexture 后 color 失效；iOS 高德无纹理线能力。
  void _addArrowTextureLine() {
    setState(() {
      _polylines = {
        ..._polylines.where((p) => p.id != 'route-arrow-texture'),
        Polyline(
          id: 'route-arrow-texture',
          points: const [
            LatLng(39.8850, 116.3700),
            LatLng(39.8850, 116.4000),
            LatLng(39.8650, 116.4100),
          ],
          width: 20,
          customTexture: BitmapDescriptor.fromIconPath(
            'assets/texture_green.png',
          ),
          joinType: JoinType.round,
          capType: CapType.round,
        ),
      };
      _lastEvent = '箭头纹理线（Android）：纹理沿线平铺，箭头随行进方向';
    });
  }

  /// 虚线类型循环：none → dash → dashDot → dot。
  void _cycleDashType() {
    _updateRouteSolid(
      (p) => p.copyWith(
        dashLineTypeParam:
            _dashTypes[(_dashTypes.indexOf(p.dashLineType) + 1) % _dashTypes.length],
      ),
    );
    setState(() {
      _lastEvent =
          'route-solid dashLineType → '
          '${_polylines.firstWhere((p) => p.id == 'route-solid').dashLineType.name}';
    });
  }

  void _cycleCapType() {
    _updateRouteSolid(
      (p) => p.copyWith(
        capTypeParam: _capTypes[(_capTypes.indexOf(p.capType) + 1) % _capTypes.length],
      ),
    );
    setState(() {
      _lastEvent =
          'route-solid capType → '
          '${_polylines.firstWhere((p) => p.id == 'route-solid').capType.name}';
    });
  }

  void _cycleJoinType() {
    _updateRouteSolid(
      (p) => p.copyWith(
        joinTypeParam:
            _joinTypes[(_joinTypes.indexOf(p.joinType) + 1) % _joinTypes.length],
      ),
    );
    setState(() {
      _lastEvent =
          'route-solid joinType → '
          '${_polylines.firstWhere((p) => p.id == 'route-solid').joinType.name}';
    });
  }

  void _cycleWidth() {
    _updateRouteSolid(
      (p) => p.copyWith(
        widthParam: _widths[(_widths.indexOf(p.width) + 1) % _widths.length],
      ),
    );
    setState(() {
      _lastEvent =
          'route-solid width → '
          '${_polylines.firstWhere((p) => p.id == 'route-solid').width}';
    });
  }

  void _cycleAlpha() {
    _updateRouteSolid(
      (p) => p.copyWith(
        alphaParam: _alphas[(_alphas.indexOf(p.alpha) + 1) % _alphas.length],
      ),
    );
    setState(() {
      _lastEvent =
          'route-solid alpha → '
          '${_polylines.firstWhere((p) => p.id == 'route-solid').alpha}';
    });
  }

  /// 平滑曲线：稀疏控制点经 Catmull-Rom 样条加密后仍是普通 Polyline，
  /// 原生在顶点间画直线段，但点足够密时视觉上就是平滑曲线。
  void _addSmoothLine() {
    const controlPoints = [
      LatLng(39.9560, 116.3720),
      LatLng(39.9460, 116.4020),
      LatLng(39.9320, 116.4240),
      LatLng(39.9120, 116.4340),
      LatLng(39.8960, 116.4180),
      LatLng(39.8900, 116.3900),
    ];
    setState(() {
      _polylines = {
        ..._polylines.where(
          (p) => p.id != 'route-smooth' && p.id != 'route-smooth-control',
        ),
        // 平滑曲线（粉）：Polyline.smooth 一行搞定
        Polyline.smooth(
          id: 'route-smooth',
          points: controlPoints,
          segmentsPerPair: 24,
          width: 8,
          color: const Color(0xFFE91E63),
          capType: CapType.round,
          joinType: JoinType.round,
        ),
        // 原始控制点折线（灰虚线）做对比
        Polyline(
          id: 'route-smooth-control',
          points: controlPoints,
          width: 2,
          color: const Color(0xFF607D8B),
          dashLineType: DashLineType.dot,
        ),
      };
      _lastEvent = '平滑曲线（粉）vs 控制点折线（灰点线）';
    });
  }

  @override
  Widget build(BuildContext context) {
    return OverlayDemoScaffold(
      title: 'Polyline 线覆盖物',
      event: _lastEvent,
      map: AMapWidget(
        initialCameraPosition: initialCamera,
        polylines: _polylines,
        onMapCreated: (controller) => _controller = controller,
      ),
      groups: [
        OverlayActionGroup('差量更新', [
          OverlayAction(Icons.timeline, '延长折线', _extendPolyline),
          OverlayAction(Icons.show_chart, '平滑曲线', _addSmoothLine),
        ]),
        OverlayActionGroup('线样式（route-solid）', [
          OverlayAction(Icons.more_horiz, '虚线类型', _cycleDashType),
          OverlayAction(Icons.horizontal_rule, '线头 capType', _cycleCapType),
          OverlayAction(Icons.turn_right, '转角 joinType', _cycleJoinType),
          OverlayAction(Icons.line_weight, '宽度', _cycleWidth),
          OverlayAction(Icons.opacity, '透明度', _cycleAlpha),
        ]),
        OverlayActionGroup('特殊线型', [
          OverlayAction(Icons.public, 'geodesic 大地曲线', _addGeodesicLine),
          OverlayAction(Icons.texture, '纹理线', _addTextureLine),
          OverlayAction(Icons.arrow_forward, '箭头纹理线', _addArrowTextureLine),
        ]),
      ],
    );
  }
}
