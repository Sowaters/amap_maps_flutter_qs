import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:amap_maps_flutter_qs/amap_maps_flutter_qs.dart';

import '../demo_config.dart';
import '../main.dart' show showDemoTip;

/// 覆盖物管理：Marker / Polyline / Polygon / Circle 的声明式差量更新。
///
/// 所有增删改都通过 setState 修改 Set 集合，插件内部 diff 后
/// 仅下发变更部分（MarkerUpdates 模式，PRD US-03）。
///
/// 本页同时演示：
/// - Marker 属性：anchor / flat / visible / zIndex / rotation / alpha
/// - 图标工厂：fromBytes / fromIconPath / fromAssetImage / defaultMarkerWithHue
/// - 两级回调：AMapWidget.onMarkerTap（全局）与 Marker.onTap（对象级）
/// - controller.showInfoWindow / hideInfoWindow（程序化控制气泡）
/// - Polyline：geodesic 大地曲线 / customTexture 纹理线 / 全部虚线类型
class OverlaysPage extends StatefulWidget {
  const OverlaysPage({super.key});

  @override
  State<OverlaysPage> createState() => _OverlaysPageState();
}

class _OverlaysPageState extends State<OverlaysPage> {
  AMapController? _controller;
  int _seq = 0;
  String _lastEvent = '试试：点击 Marker 查看气泡，长按 Marker 拖拽，'
      '双指下滑倾斜地图观察 flat 效果';

  // 天安门 Marker 的可切换属性
  bool _anchorCenter = false; // false: (0.5,1.0) 底部中心；true: (0.5,0.5) 正中
  bool _flat = false;
  bool _markerVisible = true;
  int _markerZIndex = 0;

  Set<Marker> _markers = <Marker>{};

  Set<Polyline> _polylines = <Polyline>{
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
    ),
    Polyline(
      id: 'route-dash',
      points: const [LatLng(39.8800, 116.3800), LatLng(39.8700, 116.4050)],
      width: 6,
      color: const Color(0xCC9C27B0),
      dashLineType: DashLineType.dash,
    ),
  };

  Set<Polygon> _polygons = <Polygon>{
    Polygon(
      id: 'district',
      points: const [
        LatLng(39.9400, 116.3900),
        LatLng(39.9400, 116.4200),
        LatLng(39.9200, 116.4300),
        LatLng(39.9150, 116.4000),
      ],
      strokeColor: const Color(0xFF4CAF50),
      fillColor: const Color(0x334CAF50),
      strokeWidth: 4,
    ),
  };

  Set<Circle> _circles = <Circle>{
    Circle(
      id: 'service-area',
      center: const LatLng(39.9000, 116.3900),
      radius: 600,
      strokeColor: const Color(0xFFFF5722),
      fillColor: const Color(0x22FF5722),
      strokeWidth: 4,
    ),
  };

  @override
  void initState() {
    super.initState();
    _markers = <Marker>{_tiananmen()};
  }

  /// 天安门 Marker：对象级 onTap 回调（与 AMapWidget.onMarkerTap 两级分发）。
  Marker _tiananmen() => Marker(
    id: 'tiananmen',
    position: beijingCenter,
    draggable: true,
    alpha: 0.95,
    flat: _flat,
    visible: _markerVisible,
    zIndex: _markerZIndex.toDouble(),
    anchor: _anchorCenter ? const Offset(0.5, 0.5) : const Offset(0.5, 1.0),
    infoWindow: const InfoWindow(
      title: '天安门',
      snippet: '对象级 onTap + Widget 级 onMarkerTap 两级回调',
    ),
    // 对象级回调：不经过 AMapWidget.onMarkerTap，直接分发到 Marker 自身
    onTap: (id) => setState(() => _lastEvent = 'Marker.onTap（对象级回调）：$id'),
    onDragEnd: (id, pos) => setState(() => _lastEvent = 'Marker.onDragEnd：$id'),
  );

  void _updateTiananmen(Marker Function(Marker m) transform) {
    setState(() {
      _markers = _markers.map((m) => m.id == 'tiananmen' ? transform(m) : m).toSet();
    });
  }

  // ---- Marker 增删改（差量更新） ----

  Future<void> _addRandomMarker() async {
    final random = Random();
    final id = 'marker-#${_seq++}';
    // 演示 BitmapDescriptor.fromBytes：运行时用 dart:ui 画一个圆点图标
    final icon = _seq.isEven
        ? await _renderDotIcon(Colors.deepOrange)
        : await _renderDotIcon(Colors.teal);
    final marker = Marker(
      id: id,
      position: LatLng(
        39.90 + (random.nextDouble() - 0.5) * 0.06,
        116.40 + (random.nextDouble() - 0.5) * 0.06,
      ),
      icon: icon,
      alpha: 0.9,
      rotation: random.nextDouble() * 360,
      infoWindow: InfoWindow(title: id, snippet: 'fromBytes 图标'),
    );

    setState(() {
      _markers = {..._markers, marker};
      _lastEvent = '差量新增 Marker「$id」';
    });
  }

  /// 演示 fromIconPath + fromAssetImage 两种资源图标工厂。
  Future<void> _addAssetMarker() async {
    final id = 'asset-#${_seq++}';
    // fromAssetImage：分辨率感知解析（官方 API 形状）
    final icon = await BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(),
      'assets/marker_asset.png',
    );
    setState(() {
      _markers = {
        ..._markers,
        Marker(
          id: id,
          position: const LatLng(39.9180, 116.3960),
          icon: icon,
          infoWindow: InfoWindow(title: id, snippet: 'fromAssetImage 图标'),
        ),
      };
      _lastEvent = '新增 Marker「$id」（fromAssetImage）';
    });
  }

  /// 演示 defaultMarkerWithHue：SDK 默认图标 + 色相着色。
  void _addHueMarker() {
    final id = 'hue-#${_seq++}';
    setState(() {
      _markers = {
        ..._markers,
        Marker(
          id: id,
          position: const LatLng(39.9005, 116.4005),
          icon: BitmapDescriptor.defaultMarkerWithHue(190.0),
          infoWindow: InfoWindow(title: id, snippet: 'defaultMarkerWithHue(190°)'),
        ),
      };
      _lastEvent = '新增 Marker「$id」（defaultMarkerWithHue）';
    });
  }

  void _removeLastMarker() {
    final markers = _markers
        .where((m) => m.id != 'tiananmen')
        .toList();
    if (markers.isEmpty) {
      showDemoTip(context, '没有可删除的 Marker 了');
      return;
    }
    final removed = markers.last;
    setState(() {
      _markers = {..._markers}..remove(removed);
      _lastEvent = '差量删除 Marker「${removed.id}」';
    });
  }

  void _clearMarkers() {
    setState(() {
      _markers = _markers.where((m) => m.id == 'tiananmen').toSet();
      _lastEvent = '已清空随机 Marker（天安门保留）';
    });
  }

  void _updateMarkers() {
    // 差量更新：所有随机 Marker 标题加星号，天安门换气泡文本
    setState(() {
      _markers = _markers.map((m) {
        if (m.id == 'tiananmen') {
          return m.copyWith(
            infoWindowParam: const InfoWindow(
              title: '天安门 ★',
              snippet: '标题刚被差量更新',
            ),
          );
        }
        return m.copyWith(
          infoWindowParam: InfoWindow(title: '${m.infoWindow.title ?? m.id} ★'),
        );
      }).toSet();
      _lastEvent = '差量更新全部 Marker（同 id 属性变化）';
    });
  }

  // ---- 天安门 Marker 属性切换（差量更新链路） ----

  void _toggleAnchor() {
    setState(() => _anchorCenter = !_anchorCenter);
    _updateTiananmen(
      (m) => m.copyWith(
        anchorParam: _anchorCenter
            ? const Offset(0.5, 0.5)
            : const Offset(0.5, 1.0),
      ),
    );
    setState(
      () => _lastEvent = 'anchor → ${_anchorCenter ? '(0.5, 0.5) 图标中心' : '(0.5, 1.0) 图标底部'}',
    );
  }

  void _toggleFlat() {
    setState(() => _flat = !_flat);
    _updateTiananmen((m) => m.copyWith(flatParam: _flat));
    setState(
      () => _lastEvent = 'flat → $_flat（倾斜地图可观察图标平贴/直立）',
    );
  }

  void _toggleMarkerVisible() {
    setState(() => _markerVisible = !_markerVisible);
    _updateTiananmen((m) => m.copyWith(visibleParam: _markerVisible));
    setState(() => _lastEvent = 'visible → $_markerVisible');
  }

  void _bumpZIndex() {
    final next = _markerZIndex >= 20 ? 0 : _markerZIndex + 10;
    setState(() => _markerZIndex = next);
    _updateTiananmen((m) => m.copyWith(zIndexParam: next.toDouble()));
    setState(() => _lastEvent = 'zIndex → $next（覆盖物绘制层级）');
  }

  Future<void> _showBubble() async {
    await _controller?.showInfoWindow('tiananmen');
    setState(() => _lastEvent = 'controller.showInfoWindow("tiananmen")');
  }

  Future<void> _hideBubble() async {
    await _controller?.hideInfoWindow('tiananmen');
    setState(() => _lastEvent = 'controller.hideInfoWindow("tiananmen")');
  }

  // ---- Polyline / Polygon / Circle 操作 ----

  void _extendPolyline() {
    setState(() {
      _polylines = _polylines.map((p) {
        if (p.id != 'route-solid') return p;
        final last = p.points.last;
        return p.copyWith(
          pointsParam: [
            ...p.points,
            LatLng(last.latitude - 0.008, last.longitude + 0.006),
          ],
        );
      }).toSet();
      _lastEvent = '差量更新折线（route-solid 延长一段）';
    });
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

  /// 虚线类型循环：none → dash → dashDot → dot。
  void _cycleDashType() {
    const types = [
      DashLineType.none,
      DashLineType.dash,
      DashLineType.dashDot,
      DashLineType.dot,
    ];
    setState(() {
      _polylines = _polylines.map((p) {
        if (p.id != 'route-dash') return p;
        final next = types[(types.indexOf(p.dashLineType) + 1) % types.length];
        return p.copyWith(dashLineTypeParam: next);
      }).toSet();
      _lastEvent = 'route-dash dashLineType → ${_polylines
          .firstWhere((p) => p.id == 'route-dash')
          .dashLineType.name}';
    });
  }

  void _togglePolygonFill() {
    setState(() {
      _polygons = _polygons.map((p) {
        final filled = p.fillColor == const Color(0x334CAF50);
        return p.copyWith(
          fillColorParam: filled
              ? const Color(0x33FF9800)
              : const Color(0x334CAF50),
          strokeColorParam: filled
              ? const Color(0xFFFF9800)
              : const Color(0xFF4CAF50),
        );
      }).toSet();
      _lastEvent = '差量更新多边形（换色）';
    });
  }

  void _resizeCircle(double delta) {
    setState(() {
      _circles = _circles.map((c) {
        if (c.id != 'service-area') return c;
        return c.copyWith(radiusParam: (c.radius + delta).clamp(100, 5000));
      }).toSet();
      final radius = _circles.first.radius;
      _lastEvent = '差量更新圆：半径 → ${radius.round()}m';
    });
  }

  // ---- Widget 级回调 ----

  void _onMarkerTap(String markerId) {
    // Widget 级回调先触发；若 Marker 自身也注册了 onTap（对象级），
    // 两者都会收到（见 _tiananmen 中的对象级回调演示）
    setState(() => _lastEvent = '点击 Marker「$markerId」（onMarkerTap Widget 级）');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('覆盖物管理')),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                AMapWidget(
                  initialCameraPosition: initialCamera,
                  markers: _markers,
                  polylines: _polylines,
                  polygons: _polygons,
                  circles: _circles,
                  onMapCreated: (controller) => _controller = controller,
                  onMarkerTap: _onMarkerTap,
                  onInfoWindowTap: (id) =>
                      setState(() => _lastEvent = '点击气泡（infoWindowTap）：$id'),
                  onMarkerDragEnd: (id, pos) => setState(() {
                    _lastEvent =
                        'onMarkerDragEnd：「$id」拖到 '
                        '${pos.latitude.toStringAsFixed(5)}, '
                        '${pos.longitude.toStringAsFixed(5)}';
                    // 同步回 Dart 集合，保持状态与原生一致
                    _markers = _markers.map((m) {
                      return m.id == id ? m.copyWith(positionParam: pos) : m;
                    }).toSet();
                  }),
                ),
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 8,
                  child: Card(
                    color: Theme.of(context).colorScheme.inversePrimary,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        _lastEvent,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _ControlBar(
            onMarkerAction: (action) => switch (action) {
              0 => _addRandomMarker(),
              1 => _addAssetMarker(),
              2 => _addHueMarker(),
              3 => _removeLastMarker(),
              4 => _updateMarkers(),
              _ => _clearMarkers(),
            },
            onMarkerPropAction: (action) => switch (action) {
              0 => _toggleAnchor(),
              1 => _toggleFlat(),
              2 => _toggleMarkerVisible(),
              3 => _bumpZIndex(),
              4 => _showBubble(),
              _ => _hideBubble(),
            },
            onLineAction: (action) => switch (action) {
              0 => _extendPolyline(),
              1 => _addGeodesicLine(),
              2 => _addTextureLine(),
              _ => _cycleDashType(),
            },
            onPolygonTap: _togglePolygonFill,
            onCircleTap: _resizeCircle,
          ),
        ],
      ),
    );
  }
}

class _ControlBar extends StatelessWidget {
  final void Function(int) onMarkerAction;
  final void Function(int) onMarkerPropAction;
  final void Function(int) onLineAction;
  final VoidCallback onPolygonTap;
  final ValueChanged<double> onCircleTap;

  const _ControlBar({
    required this.onMarkerAction,
    required this.onMarkerPropAction,
    required this.onLineAction,
    required this.onPolygonTap,
    required this.onCircleTap,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _chip(context, Icons.add_location_alt, '加 Marker', () => onMarkerAction(0)),
                _chip(context, Icons.image, 'asset 图标', () => onMarkerAction(1)),
                _chip(context, Icons.palette, 'hue 图标', () => onMarkerAction(2)),
                _chip(context, Icons.remove_circle_outline, '删', () => onMarkerAction(3)),
                _chip(context, Icons.autorenew, '更新', () => onMarkerAction(4)),
                _chip(context, Icons.clear_all, '清空', () => onMarkerAction(5)),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _chip(context, Icons.anchor, 'anchor', () => onMarkerPropAction(0)),
                _chip(context, Icons.layers, 'flat', () => onMarkerPropAction(1)),
                _chip(context, Icons.visibility, 'visible', () => onMarkerPropAction(2)),
                _chip(context, Icons.move_up, 'zIndex', () => onMarkerPropAction(3)),
                _chip(context, Icons.message, '弹气泡', () => onMarkerPropAction(4)),
                _chip(context, Icons.message_outlined, '收气泡', () => onMarkerPropAction(5)),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _chip(context, Icons.timeline, '延长折线', () => onLineAction(0)),
                _chip(context, Icons.public, 'geodesic 线', () => onLineAction(1)),
                _chip(context, Icons.texture, '纹理线', () => onLineAction(2)),
                _chip(context, Icons.more_horiz, '虚线样式', () => onLineAction(3)),
                _chip(context, Icons.format_color_fill, '多边形换色', onPolygonTap),
                _chip(context, Icons.add_circle_outline, '圆 +500m', () => onCircleTap(500)),
                _chip(context, Icons.remove_circle_outline, '圆 -500m', () => onCircleTap(-500)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    return ActionChip(
      avatar: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: onTap,
    );
  }
}

/// 运行时用 dart:ui 绘制一个实心圆点图标，转 PNG 字节。
Future<BitmapDescriptor> _renderDotIcon(Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const center = Offset(36, 36);
  canvas.drawCircle(center, 24, Paint()..color = Colors.white);
  canvas.drawCircle(center, 19, Paint()..color = color);
  final image = await recorder.endRecording().toImage(72, 72);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
}
