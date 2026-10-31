import 'package:flutter/material.dart';

import 'package:amap_maps_flutter_qs/amap_maps_flutter_qs.dart';

import '../../demo_config.dart';
import 'common.dart';

/// Marker 属性：单对象差量属性切换 + 气泡程序化控制 + 两级回调。
///
/// 本页演示（全部通过 copyWith 差量下发原生）：
/// - anchor / flat / visible / zIndex
/// - rotation（绕锚点旋转）与 alpha（透明度）
/// - draggable（可拖拽）与 infoWindowEnable（点击不弹气泡）
/// - InfoWindow.show：添加/更新时自动弹出气泡，无需点击
/// - controller.showInfoWindow / hideInfoWindow 程序化控制
/// - 两级回调：Marker.onTap（对象级）+ AMapWidget.onMarkerTap（Widget 级）
class MarkerPropsPage extends StatefulWidget {
  const MarkerPropsPage({super.key});

  @override
  State<MarkerPropsPage> createState() => _MarkerPropsPageState();
}

class _MarkerPropsPageState extends State<MarkerPropsPage> {
  AMapController? _controller;

  // 可切换属性（当前值都体现在 _marker 里，本地留副本便于显示）
  bool _anchorCenter = false; // false: (0.5,1.0) 底部中心；true: (0.5,0.5) 正中
  bool _flat = false;
  bool _draggable = true;
  bool _infoWindowEnable = true;

  static const _alphas = [1.0, 0.75, 0.5, 0.25];
  int _alphaIndex = 0;

  static const _zIndexes = [0.0, 10.0, 20.0];
  int _zIndexIndex = 0;

  double _rotation = 0;

  late Marker _marker = _buildMarker();

  Marker _buildMarker() => Marker(
    id: 'tiananmen',
    position: beijingCenter,
    draggable: _draggable,
    alpha: _alphas[_alphaIndex],
    flat: _flat,
    rotation: _rotation,
    zIndex: _zIndexes[_zIndexIndex],
    anchor: _anchorCenter ? const Offset(0.5, 0.5) : const Offset(0.5, 1.0),
    infoWindowEnable: _infoWindowEnable,
    infoWindow: const InfoWindow(
      title: '天安门',
      snippet: '对象级 onTap + Widget 级 onMarkerTap 两级回调',
    ),
    // 对象级回调：不经过 AMapWidget.onMarkerTap，直接分发到 Marker 自身
    onTap: (id) => setState(() => _lastEvent = 'Marker.onTap（对象级回调）：$id'),
    onDragEnd: (id, pos) =>
        setState(() => _lastEvent = 'Marker.onDragEnd：$id'),
  );

  String _lastEvent =
      '试试：双指下滑倾斜地图观察 flat 效果，拖动 Marker 换位置';

  void _update(Marker Function(Marker m) transform, String event) {
    setState(() {
      _marker = transform(_marker);
      _lastEvent = event;
    });
  }

  void _toggleAnchor() {
    _anchorCenter = !_anchorCenter;
    _update(
      (m) => m.copyWith(
        anchorParam: _anchorCenter
            ? const Offset(0.5, 0.5)
            : const Offset(0.5, 1.0),
      ),
      'anchor → ${_anchorCenter ? '(0.5, 0.5) 图标中心' : '(0.5, 1.0) 图标底部'}',
    );
  }

  void _toggleFlat() {
    _flat = !_flat;
    _update(
      (m) => m.copyWith(flatParam: _flat),
      'flat → $_flat（倾斜地图可观察图标平贴/直立）',
    );
  }

  void _toggleDraggable() {
    _draggable = !_draggable;
    _update(
      (m) => m.copyWith(draggableParam: _draggable),
      'draggable → $_draggable',
    );
  }

  void _toggleVisible() {
    final next = !_marker.visible;
    _update(
      (m) => m.copyWith(visibleParam: next),
      'visible → $next',
    );
  }

  void _cycleAlpha() {
    _alphaIndex = (_alphaIndex + 1) % _alphas.length;
    _update(
      (m) => m.copyWith(alphaParam: _alphas[_alphaIndex]),
      'alpha → ${_alphas[_alphaIndex]}',
    );
  }

  void _bumpZIndex() {
    _zIndexIndex = (_zIndexIndex + 1) % _zIndexes.length;
    _update(
      (m) => m.copyWith(zIndexParam: _zIndexes[_zIndexIndex]),
      'zIndex → ${_zIndexes[_zIndexIndex]}（覆盖物绘制层级）',
    );
  }

  void _rotate45() {
    _rotation = (_rotation + 45) % 360;
    _update(
      (m) => m.copyWith(rotationParam: _rotation),
      'rotation → $_rotation°（绕锚点顺时针旋转）',
    );
  }

  /// 点击 Marker 永远不弹气泡（但回调仍然触发）。
  void _toggleInfoWindowEnable() {
    _infoWindowEnable = !_infoWindowEnable;
    _update(
      (m) => m.copyWith(infoWindowEnableParam: _infoWindowEnable),
      'infoWindowEnable → $_infoWindowEnable',
    );
  }

  /// InfoWindow.show：每次该 Marker 更新后气泡自动保持弹出。
  void _toggleAutoShow() {
    final next = !_marker.infoWindow.show;
    _update(
      (m) => m.copyWith(infoWindowParam: m.infoWindow.copyWith(showParam: next)),
      'InfoWindow.show → $next（更新时自动弹出）',
    );
  }

  Future<void> _showBubble() async {
    await _controller?.showInfoWindow('tiananmen');
    setState(() => _lastEvent = 'controller.showInfoWindow("tiananmen")');
  }

  Future<void> _hideBubble() async {
    await _controller?.hideInfoWindow('tiananmen');
    setState(() => _lastEvent = 'controller.hideInfoWindow("tiananmen")');
  }

  @override
  Widget build(BuildContext context) {
    return OverlayDemoScaffold(
      title: 'Marker 属性 · 气泡控制',
      event: _lastEvent,
      map: AMapWidget(
        initialCameraPosition: const CameraPosition(
          target: beijingCenter,
          zoom: 16,
        ),
        markers: {_marker},
        onMapCreated: (controller) => _controller = controller,
        onMarkerTap: (id) =>
            setState(() => _lastEvent = '点击 Marker「$id」（Widget 级回调，与对象级先后触发）'),
        onMarkerDragEnd: (id, pos) => setState(() {
          _lastEvent =
              '拖拽结束：「$id」→ ${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
          _marker = _marker.copyWith(positionParam: pos);
        }),
      ),
      groups: [
        OverlayActionGroup('外观属性', [
          OverlayAction(Icons.anchor, 'anchor', _toggleAnchor),
          OverlayAction(Icons.layers, 'flat', _toggleFlat),
          OverlayAction(Icons.rotate_right, 'rotation +45°', _rotate45),
          OverlayAction(Icons.opacity, 'alpha', _cycleAlpha),
          OverlayAction(Icons.move_up, 'zIndex', _bumpZIndex),
          OverlayAction(
            Icons.visibility,
            _marker.visible ? '隐藏' : '显示',
            _toggleVisible,
          ),
        ]),
        OverlayActionGroup('交互属性', [
          OverlayAction(Icons.pan_tool, 'draggable', _toggleDraggable),
          OverlayAction(
            Icons.chat_bubble_outline,
            'infoWindowEnable',
            _toggleInfoWindowEnable,
          ),
          OverlayAction(Icons.notification_add, 'InfoWindow.show', _toggleAutoShow),
        ]),
        OverlayActionGroup('程序化气泡控制', [
          OverlayAction(Icons.message, '弹气泡', _showBubble),
          OverlayAction(Icons.message_outlined, '收气泡', _hideBubble),
        ]),
      ],
    );
  }
}
