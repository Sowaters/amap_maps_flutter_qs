import 'package:flutter/material.dart';

import 'package:amap_maps_flutter_qs/amap_maps_flutter_qs.dart';

import '../demo_config.dart';
import 'overlays/common.dart';

/// 覆盖物时序回归（0.2.4）。
///
/// 回归背景：高德 Android SDK 在地图引擎就绪（mapLoaded）前调用 addMarker /
/// addPolygon 等会静默丢弃覆盖物，而插件 onMapCreated 在 PlatformView 构造时
/// 即回发（早于引擎就绪）。0.2.3 及以前，「onMapCreated 里立刻建覆盖物」或
/// 「构造参数携带初始覆盖物」在 Android 上会落进该窗口 —— 覆盖物不显示。
/// 0.2.4 起这两类调用在 mapLoaded 前被原生端缓冲、引擎就绪后按序回放。
///
/// 本页两种场景各配 4 类覆盖物（marker / polyline / polygon / circle），
/// 场景 B 还会立刻 showInfoWindow：
/// - 场景 A：覆盖物经 AMapWidget 构造参数传入（creationParams 路径）；
/// - 场景 B：onMapCreated 回调内立刻 setState 下发（通道直发路径）。
///
/// 验收标准（真机）：重建地图后，两种场景下 4 类覆盖物 + 气泡全部可见；
/// 日志显示 onMapCreated 与 mapLoaded 之间存在时间差（即曾经的丢失窗口）。
class OverlayTimingPage extends StatefulWidget {
  const OverlayTimingPage({super.key});

  @override
  State<OverlayTimingPage> createState() => _OverlayTimingPageState();
}

enum _Scenario { viaConstructor, viaOnMapCreated }

class _OverlayTimingPageState extends State<OverlayTimingPage> {
  /// 每次重建递增，作为 AMapWidget 的 Key 强制走全新建图流程，
  /// 重新触发 onMapCreated → mapLoaded 的竞态窗口。
  int _session = 0;

  _Scenario _scenario = _Scenario.viaOnMapCreated;

  AMapController? _controller;
  DateTime? _createdAt;
  DateTime? _loadedAt;

  Set<Marker> _markers = const <Marker>{};
  Set<Polyline> _polylines = const <Polyline>{};
  Set<Polygon> _polygons = const <Polygon>{};
  Set<Circle> _circles = const <Circle>{};

  String _lastEvent = '选场景后点「重建地图」，4 类覆盖物 + 气泡应全部显示';

  @override
  void initState() {
    super.initState();
    _applyScenario();
  }

  /// 场景 A：构造参数携带（creationParams 路径）；场景 B：保持空集合，
  /// 等 onMapCreated 回调里立刻填充（通道直发路径）。
  void _applyScenario() {
    if (_scenario == _Scenario.viaConstructor) {
      _buildOverlays();
    } else {
      _markers = const <Marker>{};
      _polylines = const <Polyline>{};
      _polygons = const <Polygon>{};
      _circles = const <Circle>{};
    }
  }

  void _buildOverlays() {
    _markers = <Marker>{
      Marker(
        id: 'timing-marker',
        position: beijingCenter,
        infoWindow: InfoWindow(
          title: '时序回归 Marker',
          snippet: '场景 B 下气泡也应在加载完成后自动弹出',
        ),
      ),
    };
    _polylines = <Polyline>{
      Polyline(
        id: 'timing-polyline',
        points: <LatLng>[
          LatLng(39.9050, 116.3880),
          LatLng(39.9080, 116.3950),
          LatLng(39.9130, 116.3920),
        ],
        width: 8,
        color: Color(0xFF2196F3),
      ),
    };
    _polygons = <Polygon>{
      Polygon(
        id: 'timing-polygon',
        points: <LatLng>[
          LatLng(39.9020, 116.4000),
          LatLng(39.9000, 116.4060),
          LatLng(39.8970, 116.3990),
        ],
        fillColor: Color(0x55FF9800),
        strokeColor: Color(0xFFFF9800),
      ),
    };
    _circles = <Circle>{
      Circle(
        id: 'timing-circle',
        center: LatLng(39.9160, 116.4030),
        radius: 260,
        fillColor: Color(0x559C27B0),
        strokeColor: Color(0xFF9C27B0),
      ),
    };
  }

  /// 场景 B 的核心：onMapCreated 里立刻建覆盖物 + 立刻 showInfoWindow。
  /// 0.2.3 及以前这些调用在 Android 上会落进「引擎未就绪」窗口被静默丢弃。
  void _onMapCreated(AMapController controller) {
    _controller = controller;
    _createdAt = DateTime.now();
    if (_scenario == _Scenario.viaOnMapCreated) {
      setState(_buildOverlays);
      // 不等 mapLoaded 直接弹气泡：同样走缓冲路径（marker 此刻可能
      // 还在原生缓冲区里，回放时会先建 marker 再 show）。
      controller.showInfoWindow('timing-marker');
    }
    setState(() {
      _lastEvent = 'onMapCreated @ ${_fmt(_createdAt!)}，等待 mapLoaded…';
    });
  }

  void _onMapLoaded() {
    _loadedAt = DateTime.now();
    final delta = _loadedAt!.difference(_createdAt!).inMilliseconds;
    setState(() {
      _lastEvent = 'mapLoaded @ ${_fmt(_loadedAt!)}'
          '（onMapCreated 后 ${delta}ms）→ 缓冲的覆盖物应已回放显示';
    });
  }

  static String _fmt(DateTime t) =>
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}.'
      '${(t.millisecond % 1000).toString().padLeft(3, '0')}';

  /// 换场景或重建地图：递增 session 使 AMapWidget 换 Key 全新创建。
  void _rebuild({_Scenario? scenario}) {
    setState(() {
      if (scenario != null) _scenario = scenario;
      _session++;
      _controller = null;
      _createdAt = null;
      _loadedAt = null;
      _applyScenario();
      _lastEvent = '已重建（第 $_session 次），观察 4 类覆盖物与气泡';
    });
  }

  @override
  Widget build(BuildContext context) {
    return OverlayDemoScaffold(
      title: '覆盖物时序回归（0.2.4）',
      event: _lastEvent,
      map: AMapWidget(
        key: ValueKey('timing-map-#$_session'),
        initialCameraPosition: const CameraPosition(
          target: LatLng(39.9070, 116.3960),
          zoom: 14,
        ),
        markers: _markers,
        polylines: _polylines,
        polygons: _polygons,
        circles: _circles,
        onMapCreated: _onMapCreated,
        onMapLoaded: _onMapLoaded,
      ),
      groups: [
        OverlayActionGroup('场景（先选场景，再点重建）', [
          OverlayAction(
            Icons.input,
            _scenario == _Scenario.viaConstructor ? '✓ 构造参数携带' : '构造参数携带',
            () => _rebuild(scenario: _Scenario.viaConstructor),
          ),
          OverlayAction(
            Icons.flash_on,
            _scenario == _Scenario.viaOnMapCreated
                ? '✓ onMapCreated 立刻建'
                : 'onMapCreated 立刻建',
            () => _rebuild(scenario: _Scenario.viaOnMapCreated),
          ),
        ]),
        OverlayActionGroup('验证', [
          OverlayAction(
            Icons.refresh,
            '重建地图（重新赛跑一次）',
            () => _rebuild(),
          ),
          OverlayAction(
            Icons.visibility,
            '补弹气泡',
            () async {
              await _controller?.showInfoWindow('timing-marker');
              if (context.mounted) {
                setState(() => _lastEvent = '已手动 showInfoWindow（mapLoaded 后直连路径）');
              }
            },
          ),
        ]),
      ],
    );
  }
}
