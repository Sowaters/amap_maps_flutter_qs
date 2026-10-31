import 'package:flutter/material.dart';

import 'package:amap_maps_flutter_qs/amap_maps_flutter_qs.dart';

import '../demo_config.dart';

/// 自定义气泡：任意 Flutter Widget → PNG → `InfoWindow.content`。
///
/// 插件提供 [renderWidgetToPng] 工具：把 Widget 挂到屏幕外渲染一帧后截图。
/// 原生端 [InfoWindowAdapter] 检测到 `content` 非空时接管气泡显示。
///
/// 注意：气泡是**静态快照**，内容变化需重新渲染并差量更新 Marker。
class CustomBubblePage extends StatefulWidget {
  const CustomBubblePage({super.key});

  @override
  State<CustomBubblePage> createState() => _CustomBubblePageState();
}

class _CustomBubblePageState extends State<CustomBubblePage> {
  AMapController? _controller;
  int _renderCount = 0;
  bool _rendering = false;
  String _status = '点「渲染气泡」生成自定义 Widget 气泡';

  Marker _marker(BitmapDescriptor? bubble) => Marker(
    id: 'custom-bubble',
    position: beijingCenter,
    draggable: true,
    infoWindow: bubble == null
        ? const InfoWindow(title: '默认气泡', snippet: '尚未渲染自定义内容')
        : InfoWindow(content: bubble),
  );

  Future<void> _renderBubble() async {
    if (_rendering) return;
    setState(() => _rendering = true);
    try {
      // 任意 Widget：本例为一段纯文字（包 DefaultTextStyle 保证离屏渲染有样式）
      _renderCount++;
      final png = await renderWidgetToPng(
        context,
        const DefaultTextStyle(
          style: TextStyle(fontSize: 14, color: Colors.black),
          child: Padding(
            padding: EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [Text('自定义气泡（Widget 快照）666'), Text('第二行')],
            ),
          ),
        ),
      );
      final content = BitmapDescriptor.fromBytes(png);
      setState(() {
        _markers = <Marker>{_marker(content)};
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

  Set<Marker> _markers = const <Marker>{};

  @override
  void initState() {
    super.initState();
    _markers = <Marker>{_marker(null)};
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
                  // 但整窗点击仍会触发 onInfoWindowTap（原生 setOnInfoWindowClickListener）
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
                      child: Text(
                        '$_status\n气泡为静态快照：内容变化需重新渲染并差量更新 Marker',
                        style: const TextStyle(fontSize: 12),
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
