import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:amap_maps_flutter_qs/amap_maps_flutter_qs.dart';

import 'common.dart';

/// GPS 轨迹 · 平滑曲线。
///
/// 数据来源：history_860935079244709.csv（65 个 GPS 采样点，
/// logx=纬度 logy=经度，广东东莞，约 22.697–22.703N / 113.822–113.827E）。
///
/// 本页演示：
/// - Polyline.smooth（Catmull-Rom）把 GPS 采样点连线渲染为平滑曲线，
///   与原始折线叠加对比
/// - segmentsPerPair 平滑密度实时调节
/// - WGS-84 → GCJ-02 坐标纠偏开关：GPS 原始坐标直接上高德图会偏移
///   数百米，纠偏后轨迹与道路贴合
/// - moveCamera 适配轨迹范围
class TrackPage extends StatefulWidget {
  const TrackPage({super.key});

  @override
  State<TrackPage> createState() => _TrackPageState();
}

class _TrackPageState extends State<TrackPage> {
  AMapController? _controller;

  /// GPS 原始采样点（WGS-84）。
  static const List<LatLng> _trackWgs84 = [
    LatLng(22.6993155, 113.8250168),
    LatLng(22.6991735, 113.8252129),
    LatLng(22.6991634, 113.8251636),
    LatLng(22.6989930, 113.8251471),
    LatLng(22.6991544, 113.8250108),
    LatLng(22.6990730, 113.8250877),
    LatLng(22.6990848, 113.8250742),
    LatLng(22.6990928, 113.8250738),
    LatLng(22.6990798, 113.8250490),
    LatLng(22.6991097, 113.8250293),
    LatLng(22.6991154, 113.8250369),
    LatLng(22.6991172, 113.8250375),
    LatLng(22.6991165, 113.8250549),
    LatLng(22.6990792, 113.8250284),
    LatLng(22.6990761, 113.8250304),
    LatLng(22.6990766, 113.8250314),
    LatLng(22.6990796, 113.8250244),
    LatLng(22.6990887, 113.8250275),
    LatLng(22.6990902, 113.8250279),
    LatLng(22.6990902, 113.8250281),
    LatLng(22.6990901, 113.8250280),
    LatLng(22.6990902, 113.8250281),
    LatLng(22.6990903, 113.8250282),
    LatLng(22.6991084, 113.8250499),
    LatLng(22.6991073, 113.8250482),
    LatLng(22.6991152, 113.8249943),
    LatLng(22.6991178, 113.8249916),
    LatLng(22.6991195, 113.8249897),
    LatLng(22.6991278, 113.8249886),
    LatLng(22.6992655, 113.8250994),
    LatLng(22.6992903, 113.8251158),
    LatLng(22.6992890, 113.8251149),
    LatLng(22.6994511, 113.8251885),
    LatLng(22.6994482, 113.8255586),
    LatLng(22.6992993, 113.8259119),
    LatLng(22.6988804, 113.8258096),
    LatLng(22.6978906, 113.8247339),
    LatLng(22.6994698, 113.8230154),
    LatLng(22.6994698, 113.8230154),
    LatLng(22.6998260, 113.8226222),
    LatLng(22.7000817, 113.8223792),
    LatLng(22.7005840, 113.8226002),
    LatLng(22.7012908, 113.8232447),
    LatLng(22.7019076, 113.8233443),
    LatLng(22.7022435, 113.8233108),
    LatLng(22.7031244, 113.8233395),
    LatLng(22.7031769, 113.8236094),
    LatLng(22.7030637, 113.8239856),
    LatLng(22.7028889, 113.8250152),
    LatLng(22.7029797, 113.8255305),
    LatLng(22.7030343, 113.8264798),
    LatLng(22.7029682, 113.8268246),
    LatLng(22.7029677, 113.8268255),
    LatLng(22.7029443, 113.8269387),
    LatLng(22.7026276, 113.8272449),
    LatLng(22.7017909, 113.8271402),
    LatLng(22.7012548, 113.8269693),
    LatLng(22.7007783, 113.8266877),
    LatLng(22.7001466, 113.8263917),
    LatLng(22.6995648, 113.8261190),
    LatLng(22.6993852, 113.8258763),
    LatLng(22.6995830, 113.8253199),
    LatLng(22.6993198, 113.8251379),
    LatLng(22.6992453, 113.8251001),
    LatLng(22.6991649, 113.8249526),
  ];

  static const _segmentChoices = [4, 8, 16, 32];

  bool _correctDatum = true; // WGS-84 → GCJ-02 纠偏
  bool _showSmooth = true; // 平滑曲线 vs 原始折线
  bool _showRaw = true; // 是否叠加显示原始折线（灰点线）
  int _segmentsIndex = 1; // segmentsPerPair 档位

  String _lastEvent = 'GPS 轨迹 65 点（东莞）· 绿=平滑曲线 · 灰点=原始采样点';

  /// 当前坐标系下的轨迹点。
  List<LatLng> get _track => _correctDatum
      ? _trackWgs84.map(wgs84ToGcj02).toList(growable: false)
      : _trackWgs84;

  Set<Polyline> get _polylines => {
    // 原始采样点折线（灰点线）：对照 GPS 原始形态
    if (_showRaw)
      Polyline(
        id: 'track-raw',
        points: _track,
        width: 10,
        color: const Color(0xFF000000),
        dashLineType: DashLineType.dot,
      ),
    // 平滑曲线（绿）：Catmull-Rom 加密后交给普通 Polyline 绘制
    if (_showSmooth)
      Polyline.smooth(
        id: 'track-smooth',
        points: _track,
        segmentsPerPair: _segmentChoices[_segmentsIndex],
        width: 20,
        // color: const Color(0xFF00C853),
        customTexture: BitmapDescriptor.fromIconPath(
          'assets/texture_green.png',
        ),
        capType: CapType.round,
        joinType: JoinType.round,
      ),
  };

  void _fitCamera() {
    final track = _track;
    final latitudes = track.map((p) => p.latitude).toList();
    final longitudes = track.map((p) => p.longitude).toList();
    _controller?.moveCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(
            latitudes.reduce(math.min) - 0.001,
            longitudes.reduce(math.min) - 0.001,
          ),
          northeast: LatLng(
            latitudes.reduce(math.max) + 0.001,
            longitudes.reduce(math.max) + 0.001,
          ),
        ),
        40,
      ),
    );
  }

  void _toggleSmooth() {
    setState(() {
      _showSmooth = !_showSmooth;
      _lastEvent = _showSmooth ? '显示平滑曲线' : '隐藏平滑曲线（仅原始点线）';
    });
  }

  void _toggleRaw() {
    setState(() {
      _showRaw = !_showRaw;
      _lastEvent = _showRaw ? '叠加原始采样点线' : '隐藏原始采样点线';
    });
  }

  void _toggleDatum() {
    setState(() => _correctDatum = !_correctDatum);
    _fitCamera();
    setState(() {
      _lastEvent = _correctDatum
          ? 'WGS-84 → GCJ-02 已纠偏（轨迹与道路贴合）'
          : '显示 WGS-84 原始坐标（高德地图上会有偏移）';
    });
  }

  void _cycleSegments() {
    setState(() {
      _segmentsIndex = (_segmentsIndex + 1) % _segmentChoices.length;
      _lastEvent =
          '平滑密度 segmentsPerPair → ${_segmentChoices[_segmentsIndex]}'
          '（越大越平滑）';
    });
  }

  @override
  Widget build(BuildContext context) {
    return OverlayDemoScaffold(
      title: 'GPS 轨迹 · 平滑曲线',
      event: _lastEvent,
      map: AMapWidget(
        initialCameraPosition: const CameraPosition(
          target: LatLng(22.7004, 113.8248),
          zoom: 16,
        ),
        polylines: _polylines,
        onMapCreated: (controller) {
          _controller = controller;
          // 首帧适配轨迹范围
          WidgetsBinding.instance.addPostFrameCallback((_) => _fitCamera());
        },
      ),
      groups: [
        OverlayActionGroup('轨迹显示', [
          OverlayAction(Icons.show_chart, '平滑曲线开/关', _toggleSmooth),
          OverlayAction(Icons.grain, '原始点线开/关', _toggleRaw),
          OverlayAction(Icons.auto_awesome_motion, '平滑密度', _cycleSegments),
          OverlayAction(Icons.center_focus_strong, '视角适配', _fitCamera),
        ]),
        OverlayActionGroup('坐标系', [
          OverlayAction(Icons.swap_horiz, 'WGS-84/GCJ-02 纠偏', _toggleDatum),
        ]),
      ],
    );
  }
}

/// WGS-84 → GCJ-02 火星坐标纠偏（标准公开算法，适用于中国境内坐标）。
///
/// GPS 设备记录的是 WGS-84，高德 SDK 使用 GCJ-02；不纠偏直接上图的
/// 轨迹整体偏移约 300–700 米。境外坐标原样返回。
LatLng wgs84ToGcj02(LatLng p) {
  if (_outOfChina(p.latitude, p.longitude)) return p;
  double transformLat(double x, double y) {
    var ret =
        -100.0 +
        2.0 * x +
        3.0 * y +
        0.2 * y * y +
        0.1 * x * y +
        0.2 * math.sqrt(x.abs());
    ret +=
        (20.0 * math.sin(6.0 * x * math.pi) +
            20.0 * math.sin(2.0 * x * math.pi)) *
        2.0 /
        3.0;
    ret +=
        (20.0 * math.sin(y * math.pi) + 40.0 * math.sin(y / 3.0 * math.pi)) *
        2.0 /
        3.0;
    ret +=
        (160.0 * math.sin(y / 12.0 * math.pi) +
            320 * math.sin(y * math.pi / 30.0)) *
        2.0 /
        3.0;
    return ret;
  }

  double transformLng(double x, double y) {
    var ret =
        300.0 +
        x +
        2.0 * y +
        0.1 * x * x +
        0.1 * x * y +
        0.1 * math.sqrt(x.abs());
    ret +=
        (20.0 * math.sin(6.0 * x * math.pi) +
            20.0 * math.sin(2.0 * x * math.pi)) *
        2.0 /
        3.0;
    ret +=
        (20.0 * math.sin(x * math.pi) + 40.0 * math.sin(x / 3.0 * math.pi)) *
        2.0 /
        3.0;
    ret +=
        (150.0 * math.sin(x / 12.0 * math.pi) +
            300.0 * math.sin(x / 30.0 * math.pi)) *
        2.0 /
        3.0;
    return ret;
  }

  const a = 6378245.0; // 长半轴
  const ee = 0.00669342162296594323; // 偏心率平方
  var dLat = transformLat(p.longitude - 105.0, p.latitude - 35.0);
  var dLng = transformLng(p.longitude - 105.0, p.latitude - 35.0);
  final radLat = p.latitude / 180.0 * math.pi;
  var magic = math.sin(radLat);
  magic = 1 - ee * magic * magic;
  final sqrtMagic = math.sqrt(magic);
  dLat = (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * math.pi);
  dLng = (dLng * 180.0) / (a / sqrtMagic * math.cos(radLat) * math.pi);
  return LatLng(p.latitude + dLat, p.longitude + dLng);
}

bool _outOfChina(double lat, double lng) =>
    lng < 72.004 || lng > 137.8347 || lat < 0.8293 || lat > 55.8271;
