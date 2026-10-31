import 'package:flutter/material.dart';

import 'package:amap_maps_flutter_qs/amap_maps_flutter_qs.dart';

import '../demo_config.dart';
import '../main.dart' show showDemoTip;

/// 地图事件：所有回调收集为时间日志。
class EventsPage extends StatefulWidget {
  const EventsPage({super.key});

  @override
  State<EventsPage> createState() => _EventsPageState();
}

class _EventsLog {
  final String text;
  final bool isHighlight;

  const _EventsLog(this.text, {this.isHighlight = false});
}

class _EventsPageState extends State<EventsPage> {
  final List<_EventsLog> _logs = <_EventsLog>[];
  bool _zoomGestures = true;

  void _log(String text, {bool highlight = false}) {
    setState(() {
      final time = DateTime.now().toIso8601String().substring(11, 19);
      _logs.insert(0, _EventsLog('[$time] $text', isHighlight: highlight));
      if (_logs.length > 60) _logs.removeLast();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('地图事件')),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: Stack(
              children: [
                AMapWidget(
                  initialCameraPosition: initialCamera,
                  zoomGesturesEnabled: _zoomGestures,
                  markers: <Marker>{
                    Marker(
                      id: 'event-marker',
                      position: beijingCenter,
                      draggable: true,
                      infoWindow: InfoWindow(title: '点我 / 拖拽我'),
                    ),
                  },
                  onMapLoaded: () =>
                      _log('onMapLoaded：地图加载完成', highlight: true),
                  onTap: (latLng) {
                    // 顺带演示 AMapUtil：点击点到天安门的球面距离
                    final dist = AMapUtil.distanceBetween(latLng, beijingCenter);
                    _log(
                      'onTap：${latLng.latitude.toStringAsFixed(5)}, '
                      '${latLng.longitude.toStringAsFixed(5)}'
                      '（距天安门 ${dist >= 1000 ? '${(dist / 1000).toStringAsFixed(1)}km' : '${dist.round()}m'}）',
                    );
                  },
                  onLongPress: (latLng) => _log(
                    'onLongPress：${latLng.latitude.toStringAsFixed(5)}, '
                    '${latLng.longitude.toStringAsFixed(5)}',
                  ),
                  onCameraMove: (camera) {
                    // 高频回调不进日志，避免刷屏
                  },
                  onCameraMoveEnd: (camera) => _log(
                    'onCameraMoveEnd：zoom=${camera.zoom.toStringAsFixed(2)}',
                  ),
                  onMarkerTap: (id) => _log('onMarkerTap：$id', highlight: true),
                  onInfoWindowTap: (id) =>
                      _log('onInfoWindowTap：$id', highlight: true),
                  onMarkerDragEnd: (id, pos) => _log(
                    'onMarkerDragEnd：$id → '
                    '${pos.latitude.toStringAsFixed(5)}, '
                    '${pos.longitude.toStringAsFixed(5)}',
                    highlight: true,
                  ),
                  onPoiTouched: (poi) => _log(
                    'onPoiTouched：${poi.name}（id=${poi.id}）',
                    highlight: true,
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: SizedBox(
                    width: 200,
                    child: Card(
                      child: SwitchListTile(
                        dense: true,
                        title: const Text(
                          '缩放手势',
                          style: TextStyle(fontSize: 13),
                        ),
                        value: _zoomGestures,
                        onChanged: (v) {
                          setState(() => _zoomGestures = v);
                          showDemoTip(
                            context,
                            '缩放手势已${v ? '开启' : '禁用'}（map#setGestures 动态生效）',
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
            child: Row(
              children: [
                Text(
                  '事件日志（${_logs.length}）',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(_logs.clear),
                  child: const Text('清空'),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: _logs.isEmpty
                ? const Center(child: Text('在地图上操作试试 →'))
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      final log = _logs[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 1,
                        ),
                        child: Text(
                          log.text,
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            color: log.isHighlight
                                ? Theme.of(context).colorScheme.primary
                                : null,
                            fontWeight: log.isHighlight
                                ? FontWeight.w600
                                : null,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
