import 'package:flutter/material.dart';

import 'package:amap_maps_flutter_qs/amap_maps_flutter_qs.dart';

import '../demo_config.dart';

/// 相机控制：CameraUpdate 七种工厂 + moveCamera / animateCamera 对比 +
/// 实时相机状态与可视区域查询。
class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  AMapController? _controller;
  bool _animate = true;
  CameraPosition? _lastCamera;
  LatLngBounds? _lastVisibleRegion;

  Future<void> _apply(CameraUpdate update) async {
    final controller = _controller;
    if (controller == null) return;
    if (_animate) {
      await controller.moveCamera(update, duration: 500);
    } else {
      await controller.moveCamera(update, animated: false);
    }
    await _refreshState();
  }

  Future<void> _refreshState() async {
    final controller = _controller;
    if (controller == null) return;
    final camera = await controller.getCameraPosition();
    final region = await controller.getVisibleRegion();
    if (mounted) {
      setState(() {
        _lastCamera = camera;
        _lastVisibleRegion = region;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('相机控制'),
        actions: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('动画', style: TextStyle(fontSize: 13)),
              Switch(
                value: _animate,
                onChanged: (v) => setState(() => _animate = v),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: AMapWidget(
              initialCameraPosition: initialCamera,
              onMapCreated: (controller) {
                _controller = controller;
                _refreshState();
              },
              onCameraMoveEnd: (camera) =>
                  setState(() => _lastCamera = camera),
            ),
          ),
          _StatusCard(camera: _lastCamera, region: _lastVisibleRegion),
          _CameraButtons(onApply: _apply, onRefresh: _refreshState),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final CameraPosition? camera;
  final LatLngBounds? region;

  const _StatusCard({required this.camera, required this.region});

  String _fmt(LatLng? p) => p == null
      ? '-'
      : '${p.latitude.toStringAsFixed(4)}, ${p.longitude.toStringAsFixed(4)}';

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: DefaultTextStyle(
          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('相机: target=(${_fmt(camera?.target)}) '
                  'zoom=${camera?.zoom.toStringAsFixed(2) ?? '-'} '
                  'tilt=${camera?.tilt ?? '-'} bearing=${camera?.bearing ?? '-'}'),
              const SizedBox(height: 2),
              Text('可视区域: SW(${_fmt(region?.southwest)}) '
                  'NE(${_fmt(region?.northeast)})'),
            ],
          ),
        ),
      ),
    );
  }
}

class _CameraButtons extends StatelessWidget {
  final Future<void> Function(CameraUpdate) onApply;
  final VoidCallback onRefresh;

  const _CameraButtons({required this.onApply, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          _btn('newLatLng(上海)', () => onApply(
            CameraUpdate.newLatLng(shanghaiCenter),
          )),
          _btn('newLatLngZoom(上海,12)', () => onApply(
            CameraUpdate.newLatLngZoom(shanghaiCenter, 12),
          )),
          _btn('newLatLngBounds(北京)', () => onApply(
            CameraUpdate.newLatLngBounds(beijingBounds, 50),
          )),
          _btn('newCameraPosition(tilt30)', () => onApply(
            CameraUpdate.newCameraPosition(const CameraPosition(
              target: beijingCenter,
              zoom: 16,
              tilt: 30,
              bearing: 45,
            )),
          )),
          _btn('zoomTo(15)', () => onApply(CameraUpdate.zoomTo(15))),
          _btn('zoomBy(+1)', () => onApply(CameraUpdate.zoomBy(1))),
          _btn('zoomBy(-1)', () => onApply(CameraUpdate.zoomBy(-1))),
          _btn('zoomIn()', () => onApply(CameraUpdate.zoomIn())),
          _btn('zoomOut()', () => onApply(CameraUpdate.zoomOut())),
          _btn('zoomByFocus(+2 左上焦点)', () => onApply(
            CameraUpdate.zoomByFocus(2, const Offset(120, 240)),
          )),
          _btn('scrollBy(0,-200)', () => onApply(
            CameraUpdate.scrollBy(0, -200),
          )),
          _btn('查询相机', onRefresh),
        ],
      ),
    );
  }

  Widget _btn(String label, VoidCallback onTap) {
    return FilledButton.tonal(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        minimumSize: const Size(0, 34),
        textStyle: const TextStyle(fontSize: 12),
      ),
      child: Text(label),
    );
  }
}
