import 'package:flutter_test/flutter_test.dart';
import 'package:amap_maps_flutter_qs/amap_maps_flutter_qs.dart' hide AMapWidget;

void main() {
  test('marker diff/serialize benchmark', () {
    LatLng pos(int i) => LatLng(30.0 + (i % 500) * 0.001, 120.0 + (i ~/ 500) * 0.001);

    Set<Marker> build(int n) => {
          for (var i = 0; i < n; i++)
            Marker(id: 'm_$i', position: pos(i)),
        };

    for (final n in [200, 300, 500, 1000, 2000]) {
      final prev = build(n);
      // 场景 A：全量替换（全部删除 + 全部新增）
      final empty = <Marker>{};
      // 场景 B：无变化（引用不同但内容相同）
      final same = build(n);
      // 场景 C：改 1 个
      final oneChanged = build(n).map((m) => m.id == 'm_0' ? m.copyWith(positionParam: const LatLng(31, 121)) : m).toSet();

      var sw = Stopwatch()..start();
      final full = MarkerUpdates.from(empty, prev);
      sw.stop();
      final tFull = sw.elapsedMicroseconds;

      sw = Stopwatch()..start();
      final none = MarkerUpdates.from(prev, same);
      sw.stop();
      final tNone = sw.elapsedMicroseconds;

      sw = Stopwatch()..start();
      final one = MarkerUpdates.from(prev, oneChanged);
      sw.stop();
      final tOne = sw.elapsedMicroseconds;

      // ignore: avoid_print
      print('n=$n '
          'fullAdd: $tFull us (add=${full.markersToAdd.length}) '
          'noChange: $tNone us (update=${none.markersToChange.length}, remove=${none.markersToRemove.length}) '
          'changeOne: $tOne us (update=${one.markersToChange.length})');
      expect(full.markersToAdd.length, n);
      expect(none.isEmpty, isTrue, reason: '内容相同的重建 set 应判定为无更新');
      expect(one.markersToChange.length, 1);
    }
  });
}
