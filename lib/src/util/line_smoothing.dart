import 'dart:math' as math;

import '../model/latlng.dart';

/// 折线平滑工具：把稀疏的控制点加密为平滑曲线顶点。
///
/// 算法：Catmull-Rom 样条（等价的三次 Hermite 插值形式）。
/// 高德原生 SDK 的折线在相邻顶点之间只会画直线段；想要「连线变曲线」
/// 的效果，标准做法是在 Dart 侧用样条把控制点之间插值出密集中间点，
/// 再交给普通 `Polyline` 绘制 —— Android / iOS 表现完全一致，无需
/// 任何原生改动。
///
/// 与 `Polyline.geodesic` 的区别：geodesic 是原生大地曲线（仅两点间、
/// 沿地球曲面弯曲），本工具支持任意数量、任意形状的控制点。
///
/// ⚠️ 与 `GeometryUtil` 相同的限定：直接以经纬度做平面插值，适用于
/// 城市级小范围场景；跨越大范围（数百公里以上）时建议先投影
/// （如 Web Mercator）再平滑。
abstract final class LineSmoothing {
  /// Catmull-Rom 样条平滑。
  ///
  /// [points] 控制点（≥ 2 个，少于 2 个时原样返回副本）。
  /// [segmentsPerPair] 每对相邻控制点之间插值的段数（≥ 1，越大越平滑、
  /// 顶点越多、序列化开销越大，16 ~ 32 通常足够）。
  /// [tension] 张力系数：0 = 退化为直线，1 = 标准 Catmull-Rom
  /// （大于 1 会过冲，最大截断到 2）。
  /// [closed] 为 true 时首尾相接成闭合环（可用于平滑多边形轮廓），
  /// 输出末尾会补回首点。
  ///
  /// 输出始终包含全部原始控制点，且首点在首位。
  static List<LatLng> smoothCurve(
    List<LatLng> points, {
    int segmentsPerPair = 16,
    double tension = 1.0,
    bool closed = false,
  }) {
    if (points.length < 2) return List.of(points);
    final segs = segmentsPerPair < 1 ? 1 : segmentsPerPair;
    final t = tension <= 0
        ? 0.0
        : (tension > 2 ? 2.0 : tension);
    final n = points.length;

    // 取第 i 个控制点；闭合时环形取值，开放时端点夹取
    LatLng at(int i) =>
        points[closed ? (i % n + n) % n : i.clamp(0, n - 1)];
    // 开放曲线画 n-1 段；闭合曲线画 n 段（最后一段回到首点）
    final segmentCount = closed ? n : n - 1;

    final out = <LatLng>[points.first];
    for (var i = 0; i < segmentCount; i++) {
      final p0 = at(i - 1), p1 = at(i), p2 = at(i + 1), p3 = at(i + 2);
      // Catmull-Rom 切线（张力系数缩放；控制点重合时切线自然为零，
      // 该段退化为直线）
      final m1Lat = t * 0.5 * (p2.latitude - p0.latitude);
      final m1Lng = t * 0.5 * (p2.longitude - p0.longitude);
      final m2Lat = t * 0.5 * (p3.latitude - p1.latitude);
      final m2Lng = t * 0.5 * (p3.longitude - p1.longitude);

      for (var s = 1; s <= segs; s++) {
        final u = s / segs;
        // 三次 Hermite 基函数
        final u2 = u * u;
        final u3 = u2 * u;
        final h00 = 2 * u3 - 3 * u2 + 1;
        final h10 = u3 - 2 * u2 + u;
        final h01 = -2 * u3 + 3 * u2;
        final h11 = u3 - u2;
        out.add(
          LatLng(
            h00 * p1.latitude +
                h10 * m1Lat +
                h01 * p2.latitude +
                h11 * m2Lat,
            h00 * p1.longitude +
                h10 * m1Lng +
                h01 * p2.longitude +
                h11 * m2Lng,
          ),
        );
      }
    }
    return out;
  }

  /// 平滑曲线上某段弧长近似长度（米），用于按距离控制加密密度。
  ///
  /// 实现为输出顶点的球面折线总长（Haversine 公式）。
  static double approxLength(List<LatLng> curve) {
    var total = 0.0;
    for (var i = 1; i < curve.length; i++) {
      total += _haversine(curve[i - 1], curve[i]);
    }
    return total;
  }

  static double _haversine(LatLng a, LatLng b) {
    const r = 6378137.0;
    final lat1 = a.latitude * math.pi / 180.0;
    final lat2 = b.latitude * math.pi / 180.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180.0;
    final dLng = (b.longitude - a.longitude) * math.pi / 180.0;
    final h =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLng / 2), 2);
    return 2 * r * math.asin(math.sqrt(h).toDouble());
  }
}
