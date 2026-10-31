import 'dart:math';

import 'package:flutter/material.dart';

import 'package:amap_maps_flutter_qs/amap_maps_flutter_qs.dart';

import '../../demo_config.dart';
import 'common.dart';

/// Marker 基础：声明式差量增删改 + 四种图标工厂。
///
/// 所有增删改都通过 setState 修改 Set 集合，插件内部 diff 后
/// 仅下发变更部分（MarkerUpdates 模式，PRD US-03）。
///
/// 本页演示：
/// - 差量新增 / 删除 / 更新 / 清空（同 id 视为同一对象）
/// - 图标工厂：fromBytes（运行时绘制）/ fromAssetImage（分辨率感知）/
///   fromIconPath（最常用）/ defaultMarkerWithHue（SDK 图标着色）
/// - Widget 级 onMarkerTap / onMarkerDragEnd（拖拽后同步回 Dart 集合）
class MarkerBasicPage extends StatefulWidget {
  const MarkerBasicPage({super.key});

  @override
  State<MarkerBasicPage> createState() => _MarkerBasicPageState();
}

class _MarkerBasicPageState extends State<MarkerBasicPage> {
  int _seq = 0;
  String _lastEvent = '试试：点击 Marker，长按 Marker 拖拽';

  Set<Marker> _markers = <Marker>{
    Marker(
      id: 'tiananmen',
      position: beijingCenter,
      draggable: true,
      alpha: 0.95,
      infoWindow: InfoWindow(
        title: '天安门',
        snippet: '长按可拖拽，拖完位置会同步回 Dart 集合',
      ),
    ),
  };

  /// 差量新增：运行时 fromBytes 画一个圆点图标。
  Future<void> _addRandomMarker() async {
    final random = Random();
    final id = 'marker-#${_seq++}';
    final icon = await renderDotIcon(_seq.isEven ? Colors.deepOrange : Colors.teal);
    setState(() {
      _markers = {
        ..._markers,
        Marker(
          id: id,
          position: LatLng(
            39.90 + (random.nextDouble() - 0.5) * 0.06,
            116.40 + (random.nextDouble() - 0.5) * 0.06,
          ),
          icon: icon,
          alpha: 0.9,
          rotation: random.nextDouble() * 360,
          infoWindow: InfoWindow(title: id, snippet: 'fromBytes 图标'),
        ),
      };
      _lastEvent = '差量新增 Marker「$id」';
    });
  }

  /// fromAssetImage：分辨率感知解析（官方 API 形状）。
  Future<void> _addAssetImageMarker() async {
    final id = 'asset-image-#${_seq++}';
    final icon = await BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(),
      'assets/marker_asset.png',
    );
    setState(() {
      _markers = {
        ..._markers,
        Marker(
          id: id,
          position: const LatLng(39.9180, 116.3960),
          icon: icon,
          infoWindow: InfoWindow(title: id, snippet: 'fromAssetImage 图标'),
        ),
      };
      _lastEvent = '新增 Marker「$id」（fromAssetImage）';
    });
  }

  /// fromIconPath：最常用的自定义图标方式。
  void _addIconPathMarker() {
    final id = 'icon-path-#${_seq++}';
    setState(() {
      _markers = {
        ..._markers,
        Marker(
          id: id,
          position: const LatLng(39.9040, 116.3910),
          icon: BitmapDescriptor.fromIconPath('assets/marker_asset.png'),
          infoWindow: InfoWindow(title: id, snippet: 'fromIconPath 图标'),
        ),
      };
      _lastEvent = '新增 Marker「$id」（fromIconPath）';
    });
  }

  /// defaultMarkerWithHue：SDK 默认图标 + 色相着色。
  void _addHueMarker() {
    final id = 'hue-#${_seq++}';
    setState(() {
      _markers = {
        ..._markers,
        Marker(
          id: id,
          position: const LatLng(39.9005, 116.4005),
          icon: BitmapDescriptor.defaultMarkerWithHue(190.0),
          infoWindow: InfoWindow(
            title: id,
            snippet: 'defaultMarkerWithHue(190°)',
          ),
        ),
      };
      _lastEvent = '新增 Marker「$id」（defaultMarkerWithHue）';
    });
  }

  void _removeLastMarker() {
    final markers = _markers.where((m) => m.id != 'tiananmen').toList();
    if (markers.isEmpty) {
      setState(() => _lastEvent = '没有可删除的 Marker 了');
      return;
    }
    final removed = markers.last;
    setState(() {
      _markers = {..._markers}..remove(removed);
      _lastEvent = '差量删除 Marker「${removed.id}」';
    });
  }

  /// 差量更新：同 id 属性变化 → 原生只更新该 Marker，不重建整批。
  void _updateAllMarkers() {
    setState(() {
      _markers = _markers.map((m) {
        return m.copyWith(
          infoWindowParam: m.infoWindow.title == null
              ? m.infoWindow
              : m.infoWindow.copyWith(
                  titleParam: '${m.infoWindow.title} ★',
                ),
        );
      }).toSet();
      _lastEvent = '差量更新全部 Marker（同 id，标题加 ★）';
    });
  }

  void _clearMarkers() {
    setState(() {
      _markers = _markers.where((m) => m.id == 'tiananmen').toSet();
      _lastEvent = '已清空（天安门保留）';
    });
  }

  @override
  Widget build(BuildContext context) {
    return OverlayDemoScaffold(
      title: 'Marker 增删改 · 图标工厂',
      event: _lastEvent,
      map: AMapWidget(
        initialCameraPosition: initialCamera,
        markers: _markers,
        onMarkerTap: (id) =>
            setState(() => _lastEvent = '点击 Marker「$id」（Widget 级回调）'),
        onMarkerDragEnd: (id, pos) => setState(() {
          _lastEvent =
              'onMarkerDragEnd：「$id」拖到 '
              '${pos.latitude.toStringAsFixed(5)}, '
              '${pos.longitude.toStringAsFixed(5)}';
          // 同步回 Dart 集合，保持状态与原生一致（否则下次 diff 会拖回去）
          _markers = _markers
              .map((m) => m.id == id ? m.copyWith(positionParam: pos) : m)
              .toSet();
        }),
      ),
      groups: [
        OverlayActionGroup('差量更新（改 Set → 插件内部 diff）', [
          OverlayAction(
            Icons.add_location_alt,
            '加 Marker',
            _addRandomMarker,
          ),
          OverlayAction(
            Icons.remove_circle_outline,
            '删最后一个',
            _removeLastMarker,
          ),
          OverlayAction(Icons.autorenew, '更新全部', _updateAllMarkers),
          OverlayAction(Icons.clear_all, '清空', _clearMarkers),
        ]),
        OverlayActionGroup('图标工厂', [
          OverlayAction(
            Icons.brush,
            'fromBytes',
            _addRandomMarker,
          ),
          OverlayAction(
            Icons.image,
            'fromAssetImage',
            _addAssetImageMarker,
          ),
          OverlayAction(
            Icons.insert_drive_file,
            'fromIconPath',
            _addIconPathMarker,
          ),
          OverlayAction(
            Icons.palette,
            'defaultMarkerWithHue',
            _addHueMarker,
          ),
        ]),
      ],
    );
  }
}
