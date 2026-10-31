import 'dart:ui' show Offset;

import '../model/latlng.dart';
import '../overlay/overlay.dart';
import 'amap_util.dart';

/// 折线方向箭头：根据数据点序列，沿线生成指示行进方向的 Marker。
///
/// 高德原生 `Polyline` 没有方向箭头 API（Android 有 `setFootPrintTexture`
/// 足迹纹理，但 iOS 无对应能力），因此跨端通用做法是：
/// 按 [AMapUtil.bearingBetween] 逐段计算方位角，在沿线等距位置放置
/// 旋转的箭头 [Marker]（`flat: true` 平贴地面）。箭头方向完全由
/// 传入 [points] 的顺序决定 —— 这就是「根据数据标注方向」。
///
/// ⚠️ 平台差异：Android 端 rotation 完整生效；iOS 端 MVP 阶段
/// `MAAnnotationView` 旋转尚未实现（见原生 TODO），箭头会保持朝北。
/// ⚠️ 线性插值按经纬度平面计算，适用于城市级小范围场景。
abstract final class LineArrows {
  /// 沿折线按 [intervalMeters] 等距生成方向箭头 Marker。
  ///
  /// [points] 折线顶点（≥ 2 个），顺序即行进方向。
  /// [icon] 箭头图标：图像应「尖朝上」（图像上方 = 正北），
  /// 可用 `BitmapDescriptor.fromBytes` 运行时绘制。
  /// [intervalMeters] 相邻箭头的沿线间距（米，自动截断到 ≥ 10）。
  /// [startOffsetMeters] 第一个箭头距起点的偏移（米，默认半个间距）。
  /// [idPrefix] 生成 Marker 的 id 前缀（`<idPrefix>_0`、`<idPrefix>_1`…），
  /// 固定的 id 保证差量更新可正确增删。
  ///
  /// 返回的 Marker 建议与折线一起放入 `AMapWidget`（markers + polylines）。
  static List<Marker> alongLine({
    required List<LatLng> points,
    required BitmapDescriptor icon,
    double intervalMeters = 300,
    double startOffsetMeters = -1,
    bool flat = true,
    double alpha = 0.9,
    double zIndex = 10,
    String idPrefix = 'line-arrow',
  }) {
    if (points.length < 2) return const [];
    final interval = intervalMeters < 10 ? 10 : intervalMeters;
    final startOffset = startOffsetMeters < 0 ? interval / 2 : startOffsetMeters;

    final markers = <Marker>[];
    var nextAt = startOffset; // 下一个箭头的沿线里程（米）
    var carried = 0.0; // 已累计里程（米）
    var index = 0;

    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      final segLen = AMapUtil.distanceBetween(a, b);
      // 退化段（重合点）：方向未定义，直接跳过
      if (segLen < 1e-6) continue;
      final rotation = _markerRotation(a, b);

      while (nextAt <= carried + segLen) {
        final t = (nextAt - carried) / segLen; // 段内比例 [0, 1]
        markers.add(
          Marker(
            id: '${idPrefix}_$index',
            position: LatLng(
              a.latitude + (b.latitude - a.latitude) * t,
              a.longitude + (b.longitude - a.longitude) * t,
            ),
            icon: icon,
            flat: flat,
            rotation: rotation,
            alpha: alpha,
            zIndex: zIndex,
            anchor: const Offset(0.5, 0.5),
          ),
        );
        index++;
        nextAt += interval;
      }
      carried += segLen;
    }
    return markers;
  }

  /// 方位角 → 高德 Marker 旋转角。
  ///
  /// `AMapUtil.bearingBetween` 为罗盘约定（正北 0，顺时针）；
  /// 高德 Android `setRotateAngle` 为逆时针约定，取补角换算：
  /// bearing 90°（朝东）→ rotateAngle 270°（逆时针 270° = 朝东）。
  static double _markerRotation(LatLng from, LatLng to) =>
      (360.0 - AMapUtil.bearingBetween(from, to)) % 360.0;
}
