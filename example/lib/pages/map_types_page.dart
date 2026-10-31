import 'package:flutter/material.dart';

import 'package:amap_maps_flutter_qs/amap_maps_flutter_qs.dart';

import '../demo_config.dart';

/// 地图配置：MapType / 手势 / UI 开关 / limitBounds 全部**动态更新**。
///
/// 与早期版本不同，本页不使用 ValueKey 重建地图：
/// 参数变化经 `didUpdateWidget` 差量下发（map#setMapType /
/// map#setGestures / map#setUiOptions / map#setLimitBounds），
/// 地图实例保持不变 —— 用于验证插件的运行时属性更新链路。
class MapTypesPage extends StatefulWidget {
  const MapTypesPage({super.key});

  @override
  State<MapTypesPage> createState() => _MapTypesPageState();
}

class _MapTypesPageState extends State<MapTypesPage> {
  MapType _mapType = MapType.normal;

  // 手势开关（动态更新：map#setGestures）
  bool _zoom = true;
  bool _scroll = true;
  bool _rotate = true;
  bool _tilt = true;

  // UI 开关（动态更新：map#setUiOptions）
  bool _traffic = false;
  bool _buildings = true;
  bool _labels = true;
  bool _compass = false;
  bool _scale = true;
  bool _touchPoi = true;

  // 可视范围限制（动态更新：map#setLimitBounds，仅 Android 生效）
  bool _limitBounds = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('地图配置（动态更新）')),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                AMapWidget(
                  initialCameraPosition: initialCamera,
                  mapType: _mapType,
                  minMaxZoomPreference: const MinMaxZoomPreference(3.0, 20.0),
                  zoomGesturesEnabled: _zoom,
                  scrollGesturesEnabled: _scroll,
                  rotateGesturesEnabled: _rotate,
                  tiltGesturesEnabled: _tilt,
                  trafficEnabled: _traffic,
                  buildingsEnabled: _buildings,
                  labelsEnabled: _labels,
                  compassEnabled: _compass,
                  scaleEnabled: _scale,
                  touchPoiEnabled: _touchPoi,
                  limitBounds: _limitBounds ? beijingBounds : null,
                ),
                if (_limitBounds)
                  Positioned(
                    left: 8,
                    top: 8,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 260),
                      child: Card(
                        color: Colors.orange.shade50,
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Text(
                            'limitBounds 已启用：中心点被限制在\n北京五环范围内（仅 Android）',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final type in MapType.values)
                  ChoiceChip(
                    label: Text(type.name, style: const TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                    selected: _mapType == type,
                    onSelected: (_) => setState(() => _mapType = type),
                  ),
              ],
            ),
          ),
          _SwitchRow(
            title: '手势（map#setGestures 动态生效）',
            labels: const ['缩放', '平移', '旋转', '倾斜'],
            values: [_zoom, _scroll, _rotate, _tilt],
            onChanged: (i, v) => setState(() {
              final next = [_zoom, _scroll, _rotate, _tilt]..[i] = v;
              _zoom = next[0];
              _scroll = next[1];
              _rotate = next[2];
              _tilt = next[3];
            }),
          ),
          _SwitchRow(
            title: '图层与 UI（map#setUiOptions 动态生效）',
            labels: const ['路况', '建筑', '标注', '指南针', '比例尺', 'POI点击'],
            values: [_traffic, _buildings, _labels, _compass, _scale, _touchPoi],
            onChanged: (i, v) => setState(() {
              final next = [_traffic, _buildings, _labels, _compass, _scale, _touchPoi]
                ..[i] = v;
              _traffic = next[0];
              _buildings = next[1];
              _labels = next[2];
              _compass = next[3];
              _scale = next[4];
              _touchPoi = next[5];
            }),
          ),
          _SwitchRow(
            title: '可视范围限制（map#setLimitBounds，仅 Android）',
            labels: const ['限制在北京五环'],
            values: [_limitBounds],
            onChanged: (_, v) => setState(() => _limitBounds = v),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// 一行紧凑开关组。
class _SwitchRow extends StatelessWidget {
  final String title;
  final List<String> labels;
  final List<bool> values;
  final void Function(int index, bool value) onChanged;

  const _SwitchRow({
    required this.title,
    required this.labels,
    required this.values,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: const TextStyle(fontSize: 11, color: Colors.black54)),
          SizedBox(
            height: 34,
            child: Row(
              children: [
                for (var i = 0; i < labels.length; i++)
                  Expanded(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 40,
                          height: 30,
                          child: FittedBox(
                            child: Switch(
                              value: values[i],
                              onChanged: (v) => onChanged(i, v),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            labels[i],
                            style: const TextStyle(fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
