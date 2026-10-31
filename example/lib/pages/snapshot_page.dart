import 'package:flutter/material.dart';

import 'package:amap_maps_flutter_qs/amap_maps_flutter_qs.dart';

import '../demo_config.dart';
import '../main.dart' show showDemoTip;

/// 截图与合规：takeSnapshot + 审图号查询。
class SnapshotPage extends StatefulWidget {
  const SnapshotPage({super.key});

  @override
  State<SnapshotPage> createState() => _SnapshotPageState();
}

class _SnapshotPageState extends State<SnapshotPage> {
  AMapController? _controller;
  bool _satellite = false;
  String? _contentApprovalNumber;
  String? _satelliteApprovalNumber;

  Future<void> _takeSnapshot() async {
    final controller = _controller;
    if (controller == null) return;
    final bytes = await controller.takeSnapshot();
    if (!mounted) return;
    if (bytes == null) {
      showDemoTip(context, '当前平台暂不支持 takeSnapshot（iOS 后续版本）');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('地图截图'),
        content: InteractiveViewer(
          maxScale: 4,
          child: Image.memory(bytes, fit: BoxFit.contain),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadApprovalNumbers() async {
    final controller = _controller;
    if (controller == null) return;
    final content = await controller.getMapContentApprovalNumber();
    final satellite = await controller.getSatelliteImageApprovalNumber();
    if (mounted) {
      setState(() {
        _contentApprovalNumber = content ?? '（当前平台由地图界面自动展示）';
        _satelliteApprovalNumber = satellite ?? '（当前平台由地图界面自动展示）';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('截图与合规')),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                AMapWidget(
                  // mapType 动态更新（map#setMapType），无需重建地图
                  initialCameraPosition: initialCamera,
                  mapType: _satellite ? MapType.satellite : MapType.normal,
                  onMapCreated: (controller) {
                    _controller = controller;
                    _loadApprovalNumbers();
                  },
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  // SwitchListTile 需要有界宽度：不约束 right/width 会报
                  // "BoxConstraints forces an infinite width"
                  width: 160,
                  child: Card(
                    child: SwitchListTile(
                      dense: true,
                      title: const Text('卫星图', style: TextStyle(fontSize: 13)),
                      value: _satellite,
                      onChanged: (v) => setState(() => _satellite = v),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('审图号（App 上架合规要求在地图页展示）',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text('普通地图: ${_contentApprovalNumber ?? '加载中…'}',
                      style: const TextStyle(fontSize: 12)),
                  Text('卫星地图: ${_satelliteApprovalNumber ?? '加载中…'}',
                      style: const TextStyle(fontSize: 12)),
                ],
              ),
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
                      onPressed: _takeSnapshot,
                      icon: const Icon(Icons.photo_camera, size: 18),
                      label: const Text('takeSnapshot 截图'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: _loadApprovalNumbers,
                      child: const Text('刷新审图号'),
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
