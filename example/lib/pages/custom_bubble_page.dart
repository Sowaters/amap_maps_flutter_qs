import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:amap_maps_flutter_qs/amap_maps_flutter_qs.dart';

import '../demo_config.dart';

/// 自定义气泡：任意 Flutter Widget → PNG → `InfoWindow.content`。
///
/// 插件提供 [renderWidgetToPng] 工具：把 Widget 挂到屏幕外渲染一帧后截图。
/// 原生端检测到 `content` 非空时接管气泡显示（Android InfoWindowAdapter /
/// iOS MACustomCalloutView）。
///
/// 注意：气泡是**静态快照**，内容变化需重新渲染并差量更新 Marker；
/// Widget 内部元素不可交互（整窗点击触发 onInfoWindowTap）。
class CustomBubblePage extends StatefulWidget {
  const CustomBubblePage({super.key});

  @override
  State<CustomBubblePage> createState() => _CustomBubblePageState();
}

class _CustomBubblePageState extends State<CustomBubblePage> {
  AMapController? _controller;
  int _renderCount = 0;
  bool _rendering = false;
  Uint8List? _previewPng;
  String _status = '点「渲染气泡」生成自定义 Widget 气泡';

  Marker _marker(BitmapDescriptor? bubble) => Marker(
    id: 'custom-bubble',
    position: beijingCenter,
    draggable: true,
    icon: BitmapDescriptor.fromIconPath(
      'assets/user.png',
      width: 116 * 0.3,
      height: 169 * 0.3,
    ),
    infoWindow: bubble == null
        ? const InfoWindow(title: '默认气泡', snippet: '尚未渲染自定义内容')
        : InfoWindow(content: bubble),
  );

  Set<Marker> _markers = const <Marker>{};

  @override
  void initState() {
    super.initState();
    _markers = <Marker>{_marker(null)};
  }

  /// 待截图的气泡 Widget：仿地图 App 的「店铺卡片」——
  /// 头像 + 名称/状态 + 底部信息条，底部带小尾巴。每次渲染带版本号，
  /// 用于演示「内容变化 → 重新渲染 → 差量更新 Marker」的完整链路。
  Widget _bubbleWidget(int version) {
    final bubble = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: const BoxDecoration(
                    color: Color(0xFF1976D2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.store, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      '王府井旗舰店',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '营业中 · 距您 200m',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(9),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '快照 v$version',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
                const Spacer(),
                const Text(
                  '¥98 起',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1976D2),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    // 底部小尾巴：让快照看起来更像「气泡」
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        bubble,
        CustomPaint(
          size: const Size(14, 7),
          painter: _BubbleTailPainter(color: Colors.blue.shade200),
        ),
      ],
    );
  }

  Future<void> _renderBubble() async {
    if (_rendering) return;
    setState(() => _rendering = true);
    try {
      _renderCount++;
      final snapshot = await renderWidgetToPng(
        context,
        // 离屏渲染没有 Material 祖先，包 Material 保证文字/装饰正常绘制
        Material(
          type: MaterialType.transparency,
          child: _bubbleWidget(_renderCount),
        ),
      );
      // 关键：把快照逻辑尺寸一并传给 fromBytes——iOS 的 UIImage 默认把
      // PNG 物理像素当点显示，pixelRatio 3 的快照会放大 3 倍超出屏幕
      final content = BitmapDescriptor.fromBytes(
        snapshot.png,
        width: snapshot.width,
        height: snapshot.height,
      );
      setState(() {
        _markers = <Marker>{_marker(content)};
        _previewPng = snapshot.png;
        _status = '第 $_renderCount 次渲染完成；点击 Marker 查看气泡';
      });
      // 关键：等一帧再弹气泡。markers 更新经 didUpdateWidget 在下一帧
      // 才下发 map#updateMarkers（原生端「删旧+建新」重建），若不等，
      // showInfoWindow 会作用于旧 marker，气泡随即被重建顶掉（一闪而过）
      await WidgetsBinding.instance.endOfFrame;
      await _controller?.showInfoWindow('custom-bubble');
    } finally {
      if (mounted) setState(() => _rendering = false);
    }
  }

  /// 只收起当前气泡（不改动 Marker 内容）
  Future<void> _hideBubble() async {
    await _controller?.hideInfoWindow('custom-bubble');
    setState(() => _status = '气泡已收起（Marker 未重建）');
  }

  /// 差量更新：去掉 content，恢复原生默认气泡（title/snippet）
  Future<void> _resetToDefault() async {
    setState(() {
      _markers = <Marker>{_marker(null)};
      _status = '已恢复默认气泡（差量更新 content → null）';
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await _controller?.showInfoWindow('custom-bubble');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('自定义气泡（Widget 快照）')),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                AMapWidget(
                  initialCameraPosition: const CameraPosition(
                    target: beijingCenter,
                    zoom: 14,
                  ),
                  markers: _markers,
                  onMapCreated: (controller) => _controller = controller,
                  onMarkerTap: (id) => setState(
                    () => _status = '点击 Marker（$id）：content 非空时显示自定义气泡',
                  ),
                  // 气泡是静态 PNG，无法响应内部元素交互，
                  // 但整窗点击仍会触发 onInfoWindowTap（iOS 自定义气泡除外，
                  // 见 README 平台差异：MACustomCalloutView 不回调 infoWindowTap）
                  onInfoWindowTap: (id) => setState(
                    () => _status = '点击气泡（$id）：可在此打开真实 Flutter 页面/弹窗交互',
                  ),
                ),
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 8,
                  child: Card(
                    color: Theme.of(context).colorScheme.inversePrimary,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              '$_status\n气泡为静态快照：内容变化需重新渲染并差量更新 Marker',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          // 渲染结果预览：所见即气泡所得
                          if (_previewPng != null)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.blueGrey.shade200,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.memory(
                                  _previewPng!,
                                  width: 110,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                        ],
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
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _rendering ? null : _renderBubble,
                      icon: _rendering
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.dashboard_customize, size: 18),
                      label: Text(
                        _rendering ? '渲染中…' : '渲染气泡（第 ${_renderCount + 1} 版）',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _hideBubble,
                    child: const Text('收起'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _resetToDefault,
                    child: const Text('默认气泡'),
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

/// 气泡底部小尾巴（向下的小三角）。
class _BubbleTailPainter extends CustomPainter {
  const _BubbleTailPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BubbleTailPainter oldDelegate) =>
      oldDelegate.color != color;
}
