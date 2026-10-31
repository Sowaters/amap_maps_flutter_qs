import 'dart:math' as math;
import 'dart:ui';

import 'package:clipper2/clipper2.dart';

import '../model/latlng.dart';
import '../overlay/overlay.dart';

/// 几何运算工具：计算两个形状的「不相交区域」（对称差 XOR）。
///
/// 返回结果为可直接渲染的 [Polygon] 列表（可能是多块区域，含孔洞，
/// 孔洞通过 `Polygon.holes` 表示）。
///
/// ⚠️ 注意：以经纬度作为平面坐标进行运算，适用于城市级小范围场景；
/// 跨越大范围（数百公里以上）时建议先投影（如 Web Mercator）再计算。
abstract final class GeometryUtil {
  /// 两圆的互斥区域（XOR）。
  ///
  /// [circleSegments] 为圆近似为多边形的边数，越大越圆滑、计算越慢。
  static List<Polygon> xorCircles(
    Circle a,
    Circle b, {
    int circleSegments = 96,
    String idPrefix = 'xor',
    Color fillColor = const Color(0x66FF9800),
    Color strokeColor = const Color(0xFFFF9800),
    double strokeWidth = 4,
  }) => _xorShapes(
    _circleRing(a, circleSegments),
    _circleRing(b, circleSegments),
    idPrefix: idPrefix,
    fillColor: fillColor,
    strokeColor: strokeColor,
    strokeWidth: strokeWidth,
  );

  /// 两多边形的互斥区域（XOR）。
  static List<Polygon> xorPolygons(
    Polygon a,
    Polygon b, {
    String idPrefix = 'xor',
    Color fillColor = const Color(0x66FF9800),
    Color strokeColor = const Color(0xFFFF9800),
    double strokeWidth = 4,
  }) => _xorShapes(
    a.points,
    b.points,
    idPrefix: idPrefix,
    fillColor: fillColor,
    strokeColor: strokeColor,
    strokeWidth: strokeWidth,
  );

  /// 圆与多边形的互斥区域（圆按 [circleSegments] 段近似为多边形）。
  static List<Polygon> xorCirclePolygon(
    Circle circle,
    Polygon polygon, {
    int circleSegments = 96,
    String idPrefix = 'xor',
    Color fillColor = const Color(0x66FF9800),
    Color strokeColor = const Color(0xFFFF9800),
    double strokeWidth = 4,
  }) => _xorShapes(
    _circleRing(circle, circleSegments),
    polygon.points,
    idPrefix: idPrefix,
    fillColor: fillColor,
    strokeColor: strokeColor,
    strokeWidth: strokeWidth,
  );

  /// 圆近似为多边形顶点（经纬度，米 → 度换算按当前纬度修正）。
  static List<LatLng> circleToPoints(
    LatLng center,
    double radiusMeters, {
    int segments = 96,
  }) => _circleRing(
    Circle(id: '_tmp', center: center, radius: radiusMeters),
    segments,
  );

  // ---- 内部实现 ----

  /// 圆 → 经纬度多边形环。
  static List<LatLng> _circleRing(Circle circle, int segments) {
    final n = segments < 8 ? 8 : segments;
    // 纬度方向每度约 111320 米；经度方向随纬度收缩
    final latRad = circle.center.latitude * math.pi / 180.0;
    final metersPerDegLng = 111320.0 * math.cos(latRad);
    final ring = <LatLng>[];
    for (var i = 0; i < n; i++) {
      final angle = 2 * math.pi * i / n;
      ring.add(
        LatLng(
          circle.center.latitude +
              (circle.radius * math.sin(angle)) / 111320.0,
          circle.center.longitude +
              (circle.radius * math.cos(angle)) /
                  (metersPerDegLng == 0 ? 1 : metersPerDegLng),
        ),
      );
    }
    return ring;
  }

  /// XOR 主流程：clipper 运算 → 外环/孔洞分类 → 组装 Polygon。
  static List<Polygon> _xorShapes(
    List<LatLng> ringA,
    List<LatLng> ringB, {
    required String idPrefix,
    required Color fillColor,
    required Color strokeColor,
    required double strokeWidth,
  }) {
    if (ringA.length < 3 || ringB.length < 3) return const [];

    final solution = Clipper.xorD(
      subject: [ringA.map(_toPointD).toList()],
      clip: [ringB.map(_toPointD).toList()],
      fillRule: FillRule.nonZero,
      // 默认 2 会把坐标舍入到 0.01°（约 50m 误差），改用高精度
      precision: 8,
    );

    // Clipper2 输出约定：外环有向面积为正，孔洞为负
    final outers = <List<LatLng>>[];
    final holes = <List<LatLng>>[];
    for (final path in solution) {
      final ring = path.map(_toLatLng).toList();
      if (ring.length < 3) continue;
      if (_signedArea(ring) >= 0) {
        outers.add(ring);
      } else {
        holes.add(ring);
      }
    }
    if (outers.isEmpty) return const [];

    // 把每个孔洞挂到包含它的外环上
    final holesByOuter = List.generate(outers.length, (_) => <List<LatLng>>[]);
    for (final hole in holes) {
      var best = -1;
      var bestArea = double.infinity;
      for (var i = 0; i < outers.length; i++) {
        if (!_contains(outers[i], hole.first)) continue;
        final area = _signedArea(outers[i]).abs();
        // 多层嵌套时挂到面积最小的直接外环
        if (area < bestArea) {
          bestArea = area;
          best = i;
        }
      }
      if (best >= 0) holesByOuter[best].add(hole);
    }

    return [
      for (var i = 0; i < outers.length; i++)
        Polygon(
          id: '${idPrefix}_$i',
          points: outers[i],
          holes: holesByOuter[i],
          fillColor: fillColor,
          strokeColor: strokeColor,
          strokeWidth: strokeWidth,
        ),
    ];
  }

  static PointD _toPointD(LatLng p) => PointD(p.longitude, p.latitude);

  static LatLng _toLatLng(PointD p) => LatLng(p.y, p.x);

  /// 有向面积（鞋带公式；正 = 逆时针，负 = 顺时针）。
  static double _signedArea(List<LatLng> ring) {
    var sum = 0.0;
    for (var i = 0; i < ring.length; i++) {
      final j = (i + 1) % ring.length;
      sum += ring[i].longitude * ring[j].latitude -
          ring[j].longitude * ring[i].latitude;
    }
    return sum / 2;
  }

  /// 点是否在多边形内（射线法，不处理跨经度/极区）。
  static bool _contains(List<LatLng> ring, LatLng point) {
    var inside = false;
    for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final a = ring[i];
      final b = ring[j];
      final intersect =
          (a.latitude > point.latitude) != (b.latitude > point.latitude) &&
          point.longitude <
              (b.longitude - a.longitude) *
                      (point.latitude - a.latitude) /
                      (b.latitude - a.latitude) +
                  a.longitude;
      if (intersect) inside = !inside;
    }
    return inside;
  }
}
