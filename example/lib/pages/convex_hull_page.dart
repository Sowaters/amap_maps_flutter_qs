import 'package:flutter/material.dart';

import 'package:amap_maps_flutter_qs/amap_maps_flutter_qs.dart';

import '../demo_config.dart';
import '../ui/demo_widgets.dart';
import 'overlays/common.dart';

/// 凸包围栏 demo。
///
/// 交互约定：
/// - 点击地图：按点击顺序添加围栏点（图标 assets/fence.png）；
/// - 点数 ≥ 3：实时用 [convexHull] 计算凸包并渲染为多边形；
/// - 拖拽任意围栏点：以新位置重算凸包；
/// - 撤销：按创建顺序 LIFO 回退（每次移除最后添加的点）。
class ConvexHullPage extends StatefulWidget {
  const ConvexHullPage({super.key});

  @override
  State<ConvexHullPage> createState() => _ConvexHullPageState();
}

/// 一个围栏点：marker id + 创建时的坐标。
typedef _FencePoint = ({String id, LatLng point});

/// 叉积 (a-o) × (b-o)：以经度为 x、纬度为 y。
/// > 0 左转（逆时针）、< 0 右转、= 0 三点共线。
double crossProduct(LatLng o, LatLng a, LatLng b) =>
    (a.longitude - o.longitude) * (b.latitude - o.latitude) -
    (a.latitude - o.latitude) * (b.longitude - o.longitude);

/// 凸包（Andrew's monotone chain）。
///
/// 输入点集；输出按逆时针方向排列的凸包顶点（共线点被剔除，
/// 即凸包不含非拐点）。时间复杂度 O(n log n)，n 为点数。
List<LatLng> convexHull(List<LatLng> points) {
  if (points.length <= 1) return List.from(points);
  final List<LatLng> sorted = List.from(points)
    ..sort(
      (a, b) => a.longitude.compareTo(b.longitude) != 0
          ? a.longitude.compareTo(b.longitude)
          : a.latitude.compareTo(b.latitude),
    );
  final List<LatLng> hull = [];
  // 下凸包
  for (var p in sorted) {
    while (hull.length >= 2 &&
        crossProduct(hull[hull.length - 2], hull.last, p) <= 0) {
      hull.removeLast();
    }
    hull.add(p);
  }
  final int lowerSize = hull.length;
  // 上凸包
  for (int i = sorted.length - 2; i >= 0; i--) {
    final p = sorted[i];
    while (hull.length > lowerSize &&
        crossProduct(hull[hull.length - 2], hull.last, p) <= 0) {
      hull.removeLast();
    }
    hull.add(p);
  }
  if (hull.isNotEmpty) hull.removeLast(); // 起点重复，去掉
  return hull;
}

class _ConvexHullPageState extends State<ConvexHullPage> {
  /// 围栏点集合（保持创建顺序，撤销即 removeLast）。
  final List<_FencePoint> _marks = [];

  /// 凸包多边形（单实例，固定 id 走差量更新）。
  Set<Polygon> _polygons = {};

  /// fence.png 图标（initState 异步加载，加载完成前用默认图标兜底）。
  BitmapDescriptor? _fenceIcon;

  int _seq = 0;
  String _lastAction = '等待操作';

  @override
  void initState() {
    super.initState();
    BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(),
      'assets/fence.png',
    ).then((icon) {
      if (mounted) {
        setState(() => _fenceIcon = icon);
      }
    });
  }

  // ---- 交互 ----

  /// 点击地图：按创建顺序追加围栏点。
  void _addPoint(LatLng position) {
    _marks.add((id: 'fence_${_seq++}', point: position));
    _lastAction = '添加点 #${_marks.length}';
    _rebuild();
  }

  /// 撤销：按创建顺序 LIFO 回退（移除最后添加的点）。
  void _undo() {
    if (_marks.isEmpty) {
      showDemoTip(context, '没有可撤销的点了');
      return;
    }
    final removed = _marks.removeLast();
    _lastAction = '撤销 ${removed.id}（创建序 #${_marks.length + 1}）';
    _rebuild();
  }

  /// 清空全部围栏点。
  void _clear() {
    if (_marks.isEmpty) return;
    final count = _marks.length;
    _marks.clear();
    _lastAction = '清空 $count 个点';
    _rebuild();
  }

  /// 拖拽结束：以新位置替换该点并重算凸包。
  void _onMarkerDragEnd(String markerId, LatLng endPosition) {
    final index = _marks.indexWhere((mark) => mark.id == markerId);
    if (index == -1) return;
    _marks[index] = (id: markerId, point: endPosition);
    _lastAction = '拖拽 $markerId → (${endPosition.latitude.toStringAsFixed(5)}, '
        '${endPosition.longitude.toStringAsFixed(5)})';
    _rebuild();
  }

  /// 统一重建：markers 全量集合 + 凸包多边形（≥3 点才有）。
  void _rebuild() {
    final points = _marks.map((mark) => mark.point).toList();
    final hull = points.length >= 3 ? convexHull(points) : <LatLng>[];
    setState(() {
      _polygons = hull.length >= 3
          ? <Polygon>{
              Polygon(
                id: 'fence_hull',
                points: hull,
                strokeWidth: 3,
                strokeColor: const Color(0xFF1677FF),
                fillColor: const Color(0x331677FF),
              ),
            }
          : <Polygon>{};
    });
  }

  @override
  Widget build(BuildContext context) {
    return OverlayDemoScaffold(
      title: '凸包围栏 · 凸包计算',
      event: '顶点 ${_marks.length} 个 ｜ 凸包 '
          '${_polygons.isEmpty ? '-' : _polygons.first.points.length} 边 ｜ $_lastAction',
      groups: [
        OverlayActionGroup('操作（撤销按创建顺序回退）', [
          OverlayAction(Icons.undo, '撤销上一点', _undo),
          OverlayAction(Icons.delete_sweep, '清空全部', _clear),
        ]),
      ],
      map: AMapWidget(
        initialCameraPosition: const CameraPosition(
          target: beijingCenter,
          zoom: 13,
        ),
        onTap: _addPoint,
        polygons: _polygons,
        markers: <Marker>{
          for (final (index, mark) in _marks.indexed)
            Marker(
              id: mark.id,
              position: mark.point,
              icon: _fenceIcon ?? BitmapDescriptor.defaultMarker,
              draggable: true,
              infoWindow: InfoWindow(title: '#${index + 1}'),
              onDragEnd: _onMarkerDragEnd,
            ),
        },
      ),
    );
  }
}
