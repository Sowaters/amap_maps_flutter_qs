import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:amap_maps_flutter_qs/amap_maps_flutter_qs.dart';

/// Marker 数量级压力测试页。
///
/// 用途：真机验证 200 / 500 / 1000 / 2000 个 Marker 在差量更新链路下的
/// 生成耗时与渲染流畅度。生成策略为以地图中心为原点的网格排布，
/// 全部 Marker 共用同一个图标实例（值相等，diff 不会误判更新）。
class MarkerStressPage extends StatefulWidget {
  const MarkerStressPage({super.key});

  @override
  State<MarkerStressPage> createState() => _MarkerStressPageState();
}

class _MarkerStressPageState extends State<MarkerStressPage> {
  static const LatLng _center = LatLng(39.909187, 116.397451);
  static const double _gridStep = 0.01; // 度，约 1.1km

  Set<Marker> _markers = const <Marker>{};
  String _status = '选择数量生成 Marker';
  AMapController? _controller;
  int _lastGenMs = -1;
  int _lastSubmitMs = -1;
  int _lastNativeApplyMs = -1;

  /// 网格生成 n 个 Marker（行优先，环绕地图中心）。
  ///
  /// 全部 Marker 共用同一 icon / InfoWindow 实例（值相等，diff 不会误判更新），
  /// 真正的生成压力落在 Marker 对象与序列化上。
  static Set<Marker> _generate(int n) {
    final cols = math.sqrt(n).ceil();
    final icon = BitmapDescriptor.fromIconPath(
      'assets/user.png',
      width: 116 * 0.3,
      height: 169 * 0.3,
    );
    return <Marker>{
      for (var i = 0; i < n; i++)
        Marker(
          id: 'stress_$i',
          position: LatLng(
            _center.latitude + (i ~/ cols) * _gridStep,
            _center.longitude + (i % cols) * _gridStep,
          ),
          icon: icon,
          infoWindow: InfoWindow(title: '用户 #$i', snippet: 'Marker 压力测试气泡'),
        ),
    };
  }

  Future<void> _generateMarkers(int n) async {
    final controller = _controller;
    if (controller == null) return;

    final sw = Stopwatch()..start();
    final markers = _generate(n);
    final genMs = sw.elapsedMilliseconds;

    setState(() => _markers = markers);

    // didUpdateWidget submits the diff during this frame; channel ordering lets
    // the following controller query act as a native-processing barrier.
    await WidgetsBinding.instance.endOfFrame;
    final submitMs = sw.elapsedMilliseconds;
    await controller.getCameraPosition();
    sw.stop();
    final nativeApplyMs = sw.elapsedMilliseconds - submitMs;
    if (!mounted) return;
    setState(() {
      _lastGenMs = genMs;
      _lastSubmitMs = submitMs;
      _lastNativeApplyMs = nativeApplyMs;
      _status = '$n 个 Marker：Dart 生成 ${genMs}ms，Flutter 提交 ${submitMs}ms，'
          '原生处理确认 ${nativeApplyMs}ms';
    });
  }

  Future<void> _clear() async {
    final controller = _controller;
    if (controller == null) return;
    final sw = Stopwatch()..start();
    setState(() => _markers = const <Marker>{});
    await WidgetsBinding.instance.endOfFrame;
    final submitMs = sw.elapsedMilliseconds;
    await controller.getCameraPosition();
    sw.stop();
    final nativeApplyMs = sw.elapsedMilliseconds - submitMs;
    if (!mounted) return;
    setState(() {
      _lastSubmitMs = submitMs;
      _lastNativeApplyMs = nativeApplyMs;
      _status = '已清空：Flutter 提交 ${submitMs}ms，'
          '原生处理确认 ${nativeApplyMs}ms（差量 toRemove）';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Marker 压力测试')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final n in const [200, 500, 1000, 2000])
                  FilledButton(
                    onPressed: _controller == null ? null : () => _generateMarkers(n),
                    child: Text('$n'),
                  ),
                OutlinedButton(
                  onPressed: _controller == null ? null : _clear,
                  child: const Text('清空'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '$_status（最近：生成 ${_lastGenMs}ms / 提交 ${_lastSubmitMs}ms / '
                '原生确认 ${_lastNativeApplyMs}ms）',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          Expanded(
            child: AMapWidget(
              initialCameraPosition: const CameraPosition(
                target: _center,
                zoom: 11,
              ),
              markers: _markers,
              onMapCreated: (controller) => setState(() {
                _controller = controller;
              }),
            ),
          ),
        ],
      ),
    );
  }
}
