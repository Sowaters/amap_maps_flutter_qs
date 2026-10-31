import 'package:flutter/material.dart';

import 'package:amap_maps_flutter_qs/amap_maps_flutter_qs.dart';

/// 定位蓝点：MyLocationStyleOptions 五种模式切换 + 精度圈颜色。
///
/// 说明：蓝点样式当前仅创建时下发（与 MVP 范围一致），
/// Demo 通过 ValueKey 在切换时重建地图实例。
/// 需要定位权限（demo 在 MainActivity 启动时请求）。
class MyLocationPage extends StatefulWidget {
  const MyLocationPage({super.key});

  @override
  State<MyLocationPage> createState() => _MyLocationPageState();
}

class _MyLocationPageState extends State<MyLocationPage> {
  MyLocationMode _mode = MyLocationMode.locate;
  Color _accuracyColor = const Color(0x222196F3);
  bool _enabled = true;

  @override
  Widget build(BuildContext context) {
    final map = AMapWidget(
      key: ValueKey('$_mode-$_accuracyColor-$_enabled'),
      initialCameraPosition: const CameraPosition(
        target: LatLng(39.909187, 116.397451),
        zoom: 14,
      ),
      myLocationEnabled: _enabled,
      myLocationStyleOptions: MyLocationStyleOptions(
        _enabled,
        locationMode: _mode,
        circleFillColor: _accuracyColor,
        circleStrokeColor: _accuracyColor.withValues(alpha: 0x88),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('定位蓝点')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                const Text('显示蓝点'),
                const Spacer(),
                Switch(
                  value: _enabled,
                  onChanged: (v) => setState(() => _enabled = v),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 6,
              children: [
                for (final mode in MyLocationMode.values)
                  ChoiceChip(
                    label: Text(_modeLabel(mode)),
                    selected: _mode == mode,
                    onSelected: (_) => setState(() => _mode = mode),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Wrap(
              spacing: 6,
              children: [
                const Text('精度圈:', style: TextStyle(height: 2)),
                for (final color in [
                  const Color(0x222196F3),
                  const Color(0x224CAF50),
                  const Color(0x22FF5722),
                  const Color(0x339C27B0),
                ])
                  _ColorDot(
                    color: color,
                    selected: _accuracyColor == color,
                    onTap: () => setState(() => _accuracyColor = color),
                  ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '提示：需授权定位权限；mode=locate 首次定位居中，'
                'follow 蓝点始终居中，mapRotate 随地图旋转。',
                style: TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ),
          ),
          Expanded(child: map),
        ],
      ),
    );
  }

  String _modeLabel(MyLocationMode mode) => switch (mode) {
    MyLocationMode.show => 'show',
    MyLocationMode.locate => 'locate',
    MyLocationMode.follow => 'follow',
    MyLocationMode.mapRotate => 'mapRotate',
    MyLocationMode.locationRotate => 'locationRotate',
  };
}

class _ColorDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 1),
          shape: BoxShape.circle,
          border: selected
              ? Border.all(width: 3, color: Colors.black87)
              : Border.all(color: Colors.black26),
        ),
      ),
    );
  }
}
