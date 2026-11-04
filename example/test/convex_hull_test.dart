import 'package:flutter_test/flutter_test.dart';

import 'package:amap_maps_flutter_qs/amap_maps_flutter_qs.dart';
import 'package:amap_maps_flutter_qs_example/pages/convex_hull_page.dart'
    show convexHull, crossProduct;

void main() {
  LatLng ll(double lat, double lng) => LatLng(lat, lng);

  group('crossProduct', () {
    test('逆时针左转为正、顺时针右转为负、共线为零', () {
      final o = ll(0, 0);
      expect(crossProduct(o, ll(0, 1), ll(1, 0)), greaterThan(0)); // 左转
      expect(crossProduct(o, ll(1, 0), ll(0, 1)), lessThan(0)); // 右转
      expect(crossProduct(o, ll(1, 1), ll(2, 2)), 0); // 共线
    });
  });

  group('convexHull', () {
    test('空集 / 单点 / 两点原样返回', () {
      expect(convexHull([]), isEmpty);
      expect(convexHull([ll(1, 2)]), [ll(1, 2)]);
      final two = [ll(1, 1), ll(2, 2)];
      expect(convexHull(two).toSet(), two.toSet());
    });

    test('正方形：内部点与边上的点不进入凸包', () {
      final square = [
        ll(0, 0),
        ll(0, 10),
        ll(10, 10),
        ll(10, 0),
      ];
      final withInner = [
        ...square,
        ll(5, 5), // 内部点
        ll(0, 5), // 边上的共线点
      ];
      final hull = convexHull(withInner);
      expect(hull.length, 4);
      expect(hull.toSet(), square.toSet());
    });

    test('乱序输入结果一致，且为逆时针方向', () {
      final pts = [
        ll(39.9200, 116.4000),
        ll(39.9000, 116.4200),
        ll(39.8900, 116.3950),
        ll(39.9100, 116.4100), // 内部点
        ll(39.8950, 116.4050), // 内部点
      ];
      final hull = convexHull(pts);
      expect(hull.length, 3);
      // 逆时针：相邻边叉积均 > 0（经度为 x、纬度为 y）
      for (var i = 0; i < hull.length; i++) {
        final a = hull[i];
        final b = hull[(i + 1) % hull.length];
        final c = hull[(i + 2) % hull.length];
        expect(crossProduct(a, b, c), greaterThan(0));
      }
    });

    test('全部共线：只保留两端点', () {
      final line = [ll(1, 1), ll(2, 2), ll(3, 3), ll(1.5, 1.5)];
      final hull = convexHull(line);
      expect(hull.length, 2);
      expect(hull.toSet(), {ll(1, 1), ll(3, 3)});
    });

    test('重复点不影响结果', () {
      final pts = [ll(0, 0), ll(0, 0), ll(0, 4), ll(4, 0)];
      final hull = convexHull(pts);
      expect(hull.length, 3);
      expect(hull.toSet(), {ll(0, 0), ll(0, 4), ll(4, 0)});
    });

    test('输入不被修改（纯函数）', () {
      final input = [ll(2, 2), ll(0, 0), ll(0, 4)];
      final snapshot = List.of(input);
      convexHull(input);
      expect(input, snapshot);
    });
  });
}
