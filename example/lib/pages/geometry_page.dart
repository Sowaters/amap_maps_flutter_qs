import 'package:flutter/material.dart';

import 'package:amap_maps_flutter_qs/amap_maps_flutter_qs.dart';

import '../main.dart' show showDemoTip;

/// 几何运算：两个形状的「不相交区域」（对称差 XOR）高亮演示。
///
/// 三种模式：
/// 1. 两圆 XOR —— 交叠圆产生两块月牙形
/// 2. 两多边形 XOR —— 交叠矩形产生两块 L 形
/// 3. 同心圆 XOR —— 大圆套小圆产生带孔洞的环形（Polygon.holes）
class GeometryPage extends StatefulWidget {
  const GeometryPage({super.key});

  @override
  State<GeometryPage> createState() => _GeometryPageState();
}

class _GeometryPageState extends State<GeometryPage> {
  int _mode = 0;

  static const _modeNames = ['两圆 XOR', '两多边形 XOR', '同心圆 XOR（孔洞）'];

  // 交叠双圆（间距约 1.2km，半径 800m）
  static const _circleCenterA = LatLng(39.9130, 116.3990);
  static const _circleCenterB = LatLng(39.9130, 116.4090);

  // 交叠双矩形
  static const _rectA = [
    LatLng(39.9050, 116.3930),
    LatLng(39.9200, 116.3930),
    LatLng(39.9200, 116.4090),
    LatLng(39.9050, 116.4090),
  ];
  static const _rectB = [
    LatLng(39.9110, 116.4010),
    LatLng(39.9260, 116.4010),
    LatLng(39.9260, 116.4170),
    LatLng(39.9110, 116.4170),
  ];

  // ---- XOR 结果（橙色高亮） ----
  List<Polygon> _xorResults = [];

  bool get _circleMode => _mode != 1;

  Set<Circle> get _circles {
    if (!_circleMode) return {};
    return {
      _baseCircle('geo-circle-a', _circleCenterA, 800, Colors.blue),
      _baseCircle('geo-circle-b', _circleCenterB, 800, Colors.purple),
    };
  }

  Set<Polygon> get _basePolygons {
    if (_mode != 1) return {};
    return {
      Polygon(
        id: 'geo-poly-a',
        points: _rectA,
        strokeColor: Colors.blue,
        fillColor: const Color(0x224CAF50),
        strokeWidth: 3,
      ),
      Polygon(
        id: 'geo-poly-b',
        points: _rectB,
        strokeColor: Colors.purple,
        fillColor: const Color(0x229C27B0),
        strokeWidth: 3,
      ),
    };
  }

  /// 计算 XOR 并高亮「不相交区域」。
  void _computeXor() {
    final results = switch (_mode) {
      0 => GeometryUtil.xorCircles(
        _baseCircle('a', _circleCenterA, 800, Colors.blue),
        _baseCircle('b', _circleCenterB, 800, Colors.purple),
        circleSegments: 72,
        idPrefix: 'xor-circle',
      ),
      1 => GeometryUtil.xorPolygons(
        Polygon(id: 'a', points: _rectA),
        Polygon(id: 'b', points: _rectB),
        idPrefix: 'xor-poly',
      ),
      _ => GeometryUtil.xorCircles(
        _baseCircle('a', _circleCenterA, 1500, Colors.blue),
        _baseCircle('b', _circleCenterA, 600, Colors.purple),
        circleSegments: 72,
        idPrefix: 'xor-ring',
      ),
    };
    setState(() => _xorResults = results);
    showDemoTip(
      context,
      '不相交区域：${results.length} 块'
      '${results.any((p) => p.holes.isNotEmpty) ? "（含孔洞）" : ""}',
    );
  }

  void _clearResults() => setState(() => _xorResults = []);

  Circle _baseCircle(String id, LatLng center, double radius, Color color) =>
      Circle(
        id: id,
        center: center,
        radius: radius,
        strokeColor: color.withAlpha(0xCC),
        fillColor: color.withAlpha(0x22),
        strokeWidth: 3,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('几何运算 · 不相交区域')),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                AMapWidget(
                  initialCameraPosition: const CameraPosition(
                    target: LatLng(39.9155, 116.4050),
                    zoom: 14,
                  ),
                  circles: _circles,
                  polygons: {..._basePolygons, ..._xorResults},
                ),
                Positioned(
                  left: 8,
                  top: 8,
                  // 约束最大宽度：避免文本单行撑出屏幕 / 子组件要求有界宽度
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 280),
                    child: Card(
                      color: Colors.orange.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          _mode == 1
                              ? 'XOR = 仅属于 A 或仅属于 B 的区域'
                              : _mode == 2
                                  ? '环形外圈 1500m / 内孔 600m'
                                  : '交叠圆的月牙形不相交区域',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<int>(
                    segments: [
                      for (var i = 0; i < _modeNames.length; i++)
                        ButtonSegment(value: i, label: Text(_modeNames[i])),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (selection) => setState(() {
                      _mode = selection.first;
                      _xorResults = [];
                    }),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      FilledButton.icon(
                        onPressed: _computeXor,
                        icon: const Icon(Icons.highlight_alt),
                        label: const Text('高亮不相交区域'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _clearResults,
                        icon: const Icon(Icons.layers_clear),
                        label: const Text('清除结果'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
