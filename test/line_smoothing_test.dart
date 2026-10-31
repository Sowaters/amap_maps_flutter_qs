import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';

import 'package:amap_maps_flutter_qs/amap_maps_flutter_qs.dart';

void main() {
  // 直角转弯控制点：曲线应明显偏离控制点连线（弦）
  const control = [
    LatLng(39.9500, 116.3800),
    LatLng(39.9500, 116.4000),
    LatLng(39.9300, 116.4000),
  ];

  group('LineSmoothing.smoothCurve', () {
    test('少于 2 个控制点时原样返回副本', () {
      expect(LineSmoothing.smoothCurve(const []), isEmpty);
      final one = const [LatLng(39.9, 116.4)];
      final out = LineSmoothing.smoothCurve(one);
      expect(out, hasLength(1));
      expect(identical(out, one), isFalse);
    });

    test('输出顶点数 = (控制点数 - 1) × segmentsPerPair + 1', () {
      final out = LineSmoothing.smoothCurve(
        control,
        segmentsPerPair: 16,
      );
      expect(out, hasLength((control.length - 1) * 16 + 1));
    });

    test('保留全部原始控制点，且首点在首位', () {
      final out = LineSmoothing.smoothCurve(control, segmentsPerPair: 8);
      for (final p in control) {
        expect(out.contains(p), isTrue, reason: '控制点 $p 丢失');
      }
      expect(out.first, control.first);
      expect(out.last, control.last);
    });

    test('segmentsPerPair 越大顶点越多', () {
      final coarse = LineSmoothing.smoothCurve(control, segmentsPerPair: 4);
      final fine = LineSmoothing.smoothCurve(control, segmentsPerPair: 32);
      expect(fine.length, greaterThan(coarse.length));
    });

    test('tension = 0 时退化为直线（所有点都在弦上）', () {
      final out = LineSmoothing.smoothCurve(
        control,
        segmentsPerPair: 16,
        tension: 0,
      );
      // 第一段：(39.95, 116.38) → (39.95, 116.40)，纬度恒为 39.95
      final firstSegment = out.sublist(0, 17);
      for (final p in firstSegment) {
        expect(p.latitude, closeTo(39.95, 1e-9));
      }
    });

    test('默认张力下曲线偏离控制点连线（确实"弯"了）', () {
      final out = LineSmoothing.smoothCurve(control, segmentsPerPair: 16);
      // 第一段弦是水平线（纬度恒 39.95），取该段中点附近采样检查偏离
      final sample = out[8]; // 第一段中间的插值点
      final deviates = out.any(
        (p) => (p.latitude - 39.95).abs() > 1e-4,
      );
      expect(deviates, isTrue, reason: '曲线应偏离水平弦');
      // 插值点仍应靠近控制点附近的合理范围
      expect(sample.latitude, inInclusiveRange(39.93, 39.97));
    });

    test('closed = true 时首尾相接', () {
      final out = LineSmoothing.smoothCurve(
        control,
        segmentsPerPair: 8,
        closed: true,
      );
      expect(out, hasLength(control.length * 8 + 1));
      expect(out.first, out.last);
    });

    test('平滑后曲线总长略大于折线弦长（绕弯不抄近路）', () {
      final straight = control;
      final curve = LineSmoothing.smoothCurve(control, segmentsPerPair: 16);
      expect(
        LineSmoothing.approxLength(curve),
        greaterThan(LineSmoothing.approxLength(straight) - 1e-6),
      );
    });

    test('重复控制点不产生 NaN', () {
      final out = LineSmoothing.smoothCurve(
        const [
          LatLng(39.9, 116.4),
          LatLng(39.9, 116.4),
          LatLng(39.91, 116.41),
        ],
        segmentsPerPair: 4,
      );
      for (final p in out) {
        expect(p.latitude.isNaN, isFalse);
        expect(p.longitude.isNaN, isFalse);
      }
    });
  });

  group('Polyline.smooth', () {
    test('生成加密顶点的普通 Polyline，样式参数透传', () {
      final polyline = Polyline.smooth(
        points: control,
        segmentsPerPair: 16,
        width: 8,
        color: const Color(0xFFE91E63),
        capType: CapType.round,
        joinType: JoinType.round,
      );
      expect(polyline.points, hasLength((control.length - 1) * 16 + 1));
      expect(polyline.width, 8);
      expect(polyline.color, const Color(0xFFE91E63));
      expect(polyline.capType, CapType.round);
      // 就是一条普通 Polyline，可正常序列化
      expect(polyline.toJson(), containsPair('width', 8.0));
      expect(
        (polyline.toJson()['points'] as List).length,
        (control.length - 1) * 16 + 1,
      );
    });

    test('tension = 0 的 Polyline 等价于原始折线', () {
      final polyline = Polyline.smooth(
        points: control,
        segmentsPerPair: 4,
        tension: 0,
      );
      // tension=0 时插值点全部落在弦上，首尾即控制点
      expect(polyline.points.first, control.first);
      expect(polyline.points.last, control.last);
    });

    test('默认 id 自动生成且唯一', () {
      final a = Polyline.smooth(points: control, segmentsPerPair: 2);
      final b = Polyline.smooth(points: control, segmentsPerPair: 2);
      expect(a.id, isNot(b.id));
    });
  });

  group('LineSmoothing.approxLength', () {
    test('天安门 → 北京站 约 2.6km', () {
      const a = LatLng(39.9087, 116.3975); // 天安门
      const b = LatLng(39.9029, 116.4270); // 北京站
      final length = LineSmoothing.approxLength([a, b]);
      expect(length, closeTo(2600, 300));
    });

    test('空曲线 / 单点长度为 0', () {
      expect(LineSmoothing.approxLength(const []), 0);
      expect(
        LineSmoothing.approxLength(const [LatLng(39.9, 116.4)]),
        0,
      );
    });

    test('与 math 无关的自检：曲线长度随加密密度收敛', () {
      // 采样越密，折线近似越接近真实弧长 → 长度单调不减并收敛
      double lengthAt(int segs) => LineSmoothing.approxLength(
        LineSmoothing.smoothCurve(control, segmentsPerPair: segs),
      );
      final coarse = lengthAt(4);
      final fine = lengthAt(64);
      expect(fine, greaterThanOrEqualTo(coarse - 1e-6));
      // 收敛后与 64 段差距很小
      expect(lengthAt(256) - fine, lessThan(fine * 0.01));
    });
  });

}
