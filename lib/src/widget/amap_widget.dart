import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart';

import '../controller/amap_controller.dart';
import '../model/amap_poi.dart';
import '../model/camera_position.dart';
import '../model/custom_style_options.dart';
import '../model/latlng.dart';
import '../model/latlng_bounds.dart';
import '../model/map_language.dart';
import '../model/map_type.dart';
import '../model/min_max_zoom_preference.dart';
import '../model/my_location_style_options.dart';
import '../overlay/overlay.dart';
import '../util/amap_logger.dart';

/// [AMapWidget] 创建完成回调。
typedef MapCreatedCallback = void Function(AMapController controller);

/// Marker 拖拽结束回调。
typedef MarkerDragEndCallback =
    void Function(String markerId, LatLng endPosition);

/// 地图长按事件回调。
typedef MapLongPressCallback = void Function(LatLng latLng);

/// POI 点击回调。
typedef PoiTappedCallback = void Function(AMapPoi poi);

/// 展示高德地图的 Widget。
///
/// 使用前必须先调用 [AMapInitializer.init]（见 `amap_initializer.dart`）。
///
/// ```dart
/// const AMapWidget(
///   initialCameraPosition: CameraPosition(
///     target: LatLng(39.909187, 116.397451),
///     zoom: 10,
///   ),
/// )
/// ```
class AMapWidget extends StatefulWidget {
  /// 初始相机位置。
  ///
  /// 对齐官方：不传时使用默认值（北京中心，zoom 10）。
  final CameraPosition initialCameraPosition;

  /// 地图类型。
  final MapType mapType;

  /// 地图语言（0=中文 / 1=英文）。
  ///
  /// SDK 限制：英文仅在标准地图类型（[MapType.normal]）下生效，
  /// 且不能与自定义样式（[customStyleOptions]）同时使用。
  final MapLanguage language;

  /// 地图创建完成回调，用于获得 [AMapController]。
  final MapCreatedCallback? onMapCreated;

  /// 相机移动中回调。
  final ValueChanged<CameraPosition>? onCameraMove;

  /// 相机移动结束回调。
  final ValueChanged<CameraPosition>? onCameraMoveEnd;

  /// 地图点击回调。
  final ValueChanged<LatLng>? onTap;

  /// 地图长按回调（对齐官方 [onLongPress]）。
  final ValueChanged<LatLng>? onLongPress;

  /// Marker 点击回调（markerId）。
  final ValueChanged<String>? onMarkerTap;

  /// Marker 气泡点击回调（markerId）。
  final ValueChanged<String>? onInfoWindowTap;

  /// POI 点击回调（需 [touchPoiEnabled] 为 true）。
  ///
  /// 命名对齐官方 `onPoiTouched`；旧名 [onPoiTapped] 保留为别名。
  final PoiTappedCallback? onPoiTouched;

  /// 旧版 POI 点击回调别名。
  @Deprecated('Use onPoiTouched instead')
  final PoiTappedCallback? onPoiTapped;

  /// 地图加载完成回调（首帧瓦片渲染就绪）。
  final VoidCallback? onMapLoaded;

  /// Marker 拖拽结束回调。
  final MarkerDragEndCallback? onMarkerDragEnd;

  /// 是否显示定位小蓝点。
  final bool myLocationEnabled;

  /// 定位蓝点样式（仅 [myLocationEnabled] 为 true 时生效）。
  final MyLocationStyleOptions? myLocationStyleOptions;

  /// 地图自定义样式（官方样式 ID 或本地样式数据）。
  final CustomStyleOptions? customStyleOptions;

  /// 缩放级别范围限制。
  final MinMaxZoomPreference minMaxZoomPreference;

  /// 地图中心点可视范围限制（命名对齐官方 `limitBounds`，null 表示不限制）。
  final LatLngBounds? limitBounds;

  /// 是否显示路况。
  final bool trafficEnabled;

  /// 地图 POI 是否允许点击。
  final bool touchPoiEnabled;

  /// 是否显示 3D 建筑物。
  final bool buildingsEnabled;

  /// 是否显示底图文字标注。
  final bool labelsEnabled;

  /// 是否显示指南针。
  final bool compassEnabled;

  /// 是否显示比例尺。
  final bool scaleEnabled;

  /// 是否允许缩放手势（双指捏合 / 双击）。
  final bool zoomGesturesEnabled;

  /// 是否允许平移手势（单指拖动）。
  final bool scrollGesturesEnabled;

  /// 是否允许旋转手势（双指旋转）。
  final bool rotateGesturesEnabled;

  /// 是否允许倾斜手势（双指下滑倾斜）。
  final bool tiltGesturesEnabled;

  /// Marker 集合（差量更新：id 相同视为同一覆盖物）。
  final Set<Marker> markers;

  /// Polyline 集合。
  final Set<Polyline> polylines;

  /// Polygon 集合。
  final Set<Polygon> polygons;

  /// Circle 集合。
  final Set<Circle> circles;

  /// 参与竞争的手势识别器（用于地图嵌套滚动场景）。
  ///
  /// 默认地图优先接收手势；传入自定义识别器可调整嵌套滚动时的手势竞争。
  final Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers;

  const AMapWidget({
    super.key,
    this.initialCameraPosition = const CameraPosition(
      target: LatLng(39.909187, 116.397451),
      zoom: 10,
    ),
    this.mapType = MapType.normal,
    this.language = MapLanguage.chinese,
    this.onMapCreated,
    this.onCameraMove,
    this.onCameraMoveEnd,
    this.onTap,
    this.onLongPress,
    this.onMarkerTap,
    this.onInfoWindowTap,
    this.onPoiTouched,
    @Deprecated('Use onPoiTouched instead') this.onPoiTapped,
    this.onMapLoaded,
    this.onMarkerDragEnd,
    this.myLocationEnabled = false,
    this.myLocationStyleOptions,
    this.customStyleOptions,
    this.minMaxZoomPreference = MinMaxZoomPreference.unbounded,
    this.limitBounds,
    this.trafficEnabled = false,
    this.touchPoiEnabled = true,
    this.buildingsEnabled = true,
    this.labelsEnabled = true,
    this.compassEnabled = false,
    this.scaleEnabled = true,
    this.zoomGesturesEnabled = true,
    this.scrollGesturesEnabled = true,
    this.rotateGesturesEnabled = true,
    this.tiltGesturesEnabled = true,
    this.markers = const <Marker>{},
    this.polylines = const <Polyline>{},
    this.polygons = const <Polygon>{},
    this.circles = const <Circle>{},
    this.gestureRecognizers,
  });

  @override
  State<AMapWidget> createState() => _AMapWidgetState();
}

class _AMapWidgetState extends State<AMapWidget> {
  static const String _viewType = 'amap_maps_flutter_qs/map';
  static final Set<Factory<OneSequenceGestureRecognizer>>
  _defaultGestureRecognizers = <Factory<OneSequenceGestureRecognizer>>{
    Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
  };

  /// 全局递增的 mapId，Dart 与原生通过 creationParams 保持一致，
  /// 每个地图实例持有独立的 MethodChannel。
  static int _nextMapId = 0;

  late final int _mapId = _nextMapId++;

  /// Android 及默认通道（按插件内 mapId 命名，两端经 creationParams 对齐）。
  late final MethodChannel _mapIdChannel = MethodChannel(
    'amap_maps_flutter_qs/map#$_mapId',
  );

  /// iOS 通道：按引擎 viewId 命名。
  ///
  /// viewId 来自 onPlatformViewCreated 回调，与原生 create 的 viewIdentifier
  /// 是同一个值 —— 两端天然一致，不依赖 creationParams 是否送达
  /// （部分 Flutter 版本引擎传给原生 create 的 args 为 nil）。
  MethodChannel? _iosViewChannel;

  MethodChannel get _channel => _iosViewChannel ?? _mapIdChannel;

  /// 原生 PlatformView 是否已创建。
  ///
  /// iOS 的 UiKitView 与 Android 的 initExpensiveAndroidView 均为异步创建：
  /// build() 返回后原生 AMapPlatformView（即 `map#<mapId>` 通道 handler 的
  /// 注册方）稍后才存在。创建完成前任何通道下发都会 MissingPluginException。
  bool _platformViewCreated = false;

  /// 创建完成前暂存的通道调用，创建后按序冲刷（对齐 google_maps_flutter 做法）。
  final List<(String method, Object? args)> _pendingCalls = [];

  /// 原生注册表探针是否已执行过（每个 State 只探一次，避免刷屏）。
  bool _probedNativeRegistry = false;

  /// 所在路由的转场动画（pop 开始时冻结原生地图用）。
  Animation<double>? _routeAnimation;

  /// 地图是否已冻结下发（对应原生 map#freeze / map#unfreeze）。
  bool _frozen = false;

  /// 路由转场状态监听：pop 反向动画开始 → 冻结原生地图（Android）。
  ///
  /// 背景：Android 端 Hybrid Composition 模式下地图是真实 GLSurfaceView，
  /// GL 层的 surface/EGL 销毁在 GL 线程异步完成。若等到 pop 动画结束后的
  /// widget 卸载才处理，最后一帧地图会叠在已返回的上一页上闪现 1~2 帧。
  /// 在转场开始瞬间原生侧"冻结"（截图接管 + 隐藏 GL 层），GL 层销毁的
  /// 视觉差被截图无缝覆盖；转场被取消（预测性返回滑回）则解冻恢复。
  void _onRouteAnimationStatusChanged(AnimationStatus status) {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    switch (status) {
      case AnimationStatus.reverse:
        if (!_frozen) {
          _frozen = true;
          _invokeMapMethod('map#freeze');
        }
      case AnimationStatus.completed:
        // 转场取消（路由重新置顶）→ 恢复活地图
        if (_frozen) {
          _frozen = false;
          _invokeMapMethod('map#unfreeze');
        }
      case AnimationStatus.forward || AnimationStatus.dismissed:
        break;
    }
  }

  /// 通道下发统一入口：未创建前入队，创建后直接下发。
  Future<void> _invokeMapMethod(String method, [Object? args]) async {
    if (!_platformViewCreated) {
      AMapLogger.d('map#$_mapId（未创建）暂存通道调用: $method');
      _pendingCalls.add((method, args));
      return;
    }
    AMapLogger.d('map#$_mapId -> $method ${_briefArgs(args)}');
    try {
      await _channel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      // 原生地图实例已销毁（如页面快速关闭 / dispose 后的迟到调用），静默丢弃
      AMapLogger.w(
        'map#$_mapId -> $method 调用失败：原生实例不存在（MissingPluginException）',
      );
      unawaited(_probeNativeRegistry());
    }
  }

  /// 诊断探针：per-map 通道不通时，经主通道查询原生端实际注册的地图通道。
  ///
  /// - 若探针本身也抛 MissingPluginException → 设备上的原生代码不是最新构建
  ///   （日志里也看不到 `[AMapQS] register：注册主通道 ...`），需 flutter clean 重建。
  /// - 若返回的 maps 为空 → 原生 create 从未执行（PlatformView 注册问题）。
  /// - 若包含本地图的通道但调用仍失败 → 需检查 messenger 一致性。
  ///   注意 iOS 端通道按引擎 viewId 命名，可能与插件 mapId 计数不一致。
  Future<void> _probeNativeRegistry() async {
    if (_probedNativeRegistry) return;
    _probedNativeRegistry = true;
    try {
      final info = await MethodChannel(
        'amap_maps_flutter_qs',
      ).invokeMethod<dynamic>('debug#listMaps');
      AMapLogger.w(
        'map#$_mapId 原生注册表探针结果: $info'
        '（iOS 期望包含 "amap_maps_flutter_qs/map#<viewId>"，viewId 见上方创建日志）',
      );
    } catch (e) {
      AMapLogger.w(
        'map#$_mapId 原生注册表探针也失败（$e）→ 设备上运行的原生代码不是最新构建，'
        '请执行 flutter clean 后重新运行',
      );
    }
  }

  /// iOS 平台视图创建回调。
  ///
  /// 通道改按 viewId 命名（原生 create 的 viewIdentifier 与此同值，天然一致），
  /// 此处把 handler 从 mapId 通道迁移到 viewId 通道，并经主通道 `map#attach`
  /// 补送 creationParams（部分 Flutter 版本引擎传给原生 create 的 args 为 nil，
  /// 原生需补参数应用初始配置）并触发原生回发 mapCreated。
  Future<void> _onIosPlatformViewCreated(int viewId) async {
    _iosViewChannel = MethodChannel('amap_maps_flutter_qs/map#$viewId');
    _iosViewChannel!.setMethodCallHandler(_handleNativeCall);
    // 仅在通道名不同时才迁移 handler：引擎 viewId 与插件 mapId 计数器通常
    // 相等（均从 0 递增），此时两个通道同名 —— MethodChannel 的 handler 按
    // 名字注册到 root messenger，对同名 _mapIdChannel 清 handler 会把刚挂
    // 的 _handleNativeCall 一并清空，原生所有事件（mapLoaded/mapTap/
    // cameraMoveEnd/markerTap…）将无人接收（EventsPage「没有事件返回」根因；
    // Dart→Native 方向不受影响，故地图/覆盖物/相机此前一直正常）。
    if (viewId != _mapId) {
      _mapIdChannel.setMethodCallHandler(null);
    }
    AMapLogger.d('map#$_mapId（viewId=$viewId）iOS 通道已按 viewId 就绪');
    try {
      final attached = await MethodChannel(
        'amap_maps_flutter_qs',
      ).invokeMethod<dynamic>('map#attach', <String, Object?>{
        'viewId': viewId,
        'params': _creationParams,
      });
      AMapLogger.d(
        'map#$_mapId attach 结果：$attached'
        '（viewId=参数已补送 / -2=create 时参数已送达 / -3=原生无此视图）',
      );
    } catch (e) {
      AMapLogger.w('map#$_mapId attach 握手失败: $e');
    }
    _markPlatformViewCreated();
    _fireOnMapCreated();
  }

  /// PlatformView 创建完成（framework onPlatformViewCreated 与原生 mapCreated
  /// 两条路径都会到达，幂等）。
  void _markPlatformViewCreated() {
    if (_platformViewCreated) return;
    _platformViewCreated = true;
    AMapLogger.d(
      'map#$_mapId platform view created（冲刷 ${_pendingCalls.length} 条暂存调用）',
    );
    if (_pendingCalls.isEmpty) return;
    final calls = List.of(_pendingCalls);
    _pendingCalls.clear();
    for (final (method, args) in calls) {
      _invokeMapMethod(method, args);
    }
  }

  /// onMapCreated 只回调一次。
  ///
  /// 两条路径竞争：iOS 在 attach 握手后由 Dart 主动触发；原生 mapCreated
  /// 事件（iOS attach 回发 / Android 创建完成回发）也会到达。幂等保护。
  bool _onMapCreatedFired = false;

  void _fireOnMapCreated() {
    if (_onMapCreatedFired) return;
    _onMapCreatedFired = true;
    AMapLogger.d(
      'map#$_mapId onMapCreated 回调'
      '${widget.onMapCreated == null ? "（未注册，跳过）" : ""}',
    );
    widget.onMapCreated?.call(
      AMapController.createFor(_mapId, channel: _channel),
    );
  }

  @override
  void initState() {
    super.initState();
    AMapLogger.d('map#$_mapId initState creationParams: ${_briefArgs(_creationParams)}');
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 挂接所在路由的转场动画（pop 冻结机制依赖它）
    final animation = ModalRoute.of(context)?.animation;
    if (!identical(animation, _routeAnimation)) {
      _routeAnimation?.removeStatusListener(_onRouteAnimationStatusChanged);
      _routeAnimation = animation;
      animation?.addStatusListener(_onRouteAnimationStatusChanged);
    }
  }

  @override
  void didUpdateWidget(AMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 覆盖物差量更新：仅下发增 / 删 / 改三部分（US-03）
    if (!identical(oldWidget.markers, widget.markers)) {
      final updates = MarkerUpdates.from(oldWidget.markers, widget.markers);
      if (!updates.isEmpty) {
        AMapLogger.d('map#$_mapId 覆盖物差异 markers: ${updates.toJson()}');
        _invokeMapMethod('map#updateMarkers', updates.toJson());
      }
    }
    if (!identical(oldWidget.polylines, widget.polylines)) {
      final updates = PolylineUpdates.from(
        oldWidget.polylines,
        widget.polylines,
      );
      if (!updates.isEmpty) {
        _invokeMapMethod('map#updatePolylines', updates.toJson());
      }
    }
    if (!identical(oldWidget.polygons, widget.polygons)) {
      final updates = PolygonUpdates.from(oldWidget.polygons, widget.polygons);
      if (!updates.isEmpty) {
        _invokeMapMethod('map#updatePolygons', updates.toJson());
      }
    }
    if (!identical(oldWidget.circles, widget.circles)) {
      final updates = CircleUpdates.from(oldWidget.circles, widget.circles);
      if (!updates.isEmpty) {
        _invokeMapMethod('map#updateCircles', updates.toJson());
      }
    }
    if (oldWidget.mapType != widget.mapType) {
      _invokeMapMethod('map#setMapType', widget.mapType.toJson());
    }
    if (oldWidget.language != widget.language) {
      _invokeMapMethod('map#setLanguage', widget.language.toJson());
    }
    if (oldWidget.minMaxZoomPreference != widget.minMaxZoomPreference) {
      _invokeMapMethod(
        'map#setMinMaxZoomPreference',
        widget.minMaxZoomPreference.toJson(),
      );
    }
    if (oldWidget.limitBounds != widget.limitBounds) {
      _invokeMapMethod('map#setLimitBounds', widget.limitBounds?.toJson());
    }
    // 手势开关：任一变化即整体下发
    final gesturesChanged =
        oldWidget.zoomGesturesEnabled != widget.zoomGesturesEnabled ||
        oldWidget.scrollGesturesEnabled != widget.scrollGesturesEnabled ||
        oldWidget.rotateGesturesEnabled != widget.rotateGesturesEnabled ||
        oldWidget.tiltGesturesEnabled != widget.tiltGesturesEnabled;
    if (gesturesChanged) {
      _invokeMapMethod('map#setGestures', _gestures);
    }
    // UI 开关类选项：任一变化即整体下发（原生端逐项应用）
    final uiChanged =
        oldWidget.trafficEnabled != widget.trafficEnabled ||
        oldWidget.touchPoiEnabled != widget.touchPoiEnabled ||
        oldWidget.buildingsEnabled != widget.buildingsEnabled ||
        oldWidget.labelsEnabled != widget.labelsEnabled ||
        oldWidget.compassEnabled != widget.compassEnabled ||
        oldWidget.scaleEnabled != widget.scaleEnabled;
    if (uiChanged) {
      _invokeMapMethod('map#setUiOptions', _uiOptions);
    }
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_onRouteAnimationStatusChanged);
    _pendingCalls.clear();
    // 驱动原生释放地图资源。iOS 引擎没有 FlutterPlatformView.dispose 生命周期
    // （协议只有 view），MAMapView 又是有限资源（同时约 10 个），不显式释放
    // 会导致连续开关地图页后新地图创建失败。Android 引擎会自动调 dispose，
    // 此消息为幂等兜底（未识别的 method 返回 notImplemented，无副作用）。
    // 通道若已被原生销毁（快速关闭页面），MissingPluginException 静默忽略。
    _mapIdChannel.invokeMethod<void>('map#dispose').then((_) {}, onError: (_) {});
    _mapIdChannel.setMethodCallHandler(null);
    _iosViewChannel?.setMethodCallHandler(null);
    super.dispose();
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    AMapLogger.d('map#$_mapId <- native ${call.method} ${_briefArgs(call.arguments)}');
    switch (call.method) {
      case 'mapCreated':
        // 原生通知（iOS 经 attach 握手回发；Android 创建完成时回发），幂等
        _markPlatformViewCreated();
        _fireOnMapCreated();
      case 'mapLoaded':
        widget.onMapLoaded?.call();
      case 'cameraMove':
        widget.onCameraMove?.call(
          CameraPosition.fromJson(call.arguments) ??
              widget.initialCameraPosition,
        );
      case 'cameraMoveEnd':
        widget.onCameraMoveEnd?.call(
          CameraPosition.fromJson(call.arguments) ??
              widget.initialCameraPosition,
        );
      case 'mapTap':
        final latLng = LatLng.fromJson(call.arguments);
        if (latLng != null) widget.onTap?.call(latLng);
      case 'mapLongPress':
        final latLng = LatLng.fromJson(call.arguments);
        if (latLng != null) widget.onLongPress?.call(latLng);
      case 'markerTap' || 'infoWindowTap':
        final id = call.arguments as String?;
        final marker = _findMarker(id);
        if (call.method == 'markerTap') {
          widget.onMarkerTap?.call(id!);
        } else {
          widget.onInfoWindowTap?.call(id!);
        }
        if (marker == null) return;
        final infoWindowTap = call.method == 'infoWindowTap';
        final callback = infoWindowTap
            ? (marker.infoWindow.onTap ?? marker.onTap)
            : (marker.onTap ?? marker.infoWindow.onTap);
        callback?.call(marker.id);
      case 'poiTap':
        final poi = AMapPoi.fromJson(call.arguments);
        if (poi != null) {
          widget.onPoiTouched?.call(poi);
          // ignore: deprecated_member_use_from_same_package
          widget.onPoiTapped?.call(poi);
        }
      case 'markerDragEnd':
        final args = call.arguments as Map<dynamic, dynamic>;
        final id = args['id'] as String?;
        final endPosition = LatLng.fromJson(args['position']);
        if (id == null || endPosition == null) return;
        widget.onMarkerDragEnd?.call(id, endPosition);
        _findMarker(id)?.onDragEnd?.call(id, endPosition);
      default:
        AMapLogger.w('map#$_mapId 收到未处理的原生事件: ${call.method}（该功能可能在当前平台未实现）');
        throw MissingPluginException('Unknown method ${call.method}');
    }
  }

  /// 参数摘要（截断长内容，避免日志刷屏）。
  static String _briefArgs(Object? args) {
    if (args == null) return '';
    final s = args.toString();
    return s.length > 200 ? '${s.substring(0, 200)}…' : s;
  }

  Marker? _findMarker(String? id) {
    if (id == null) return null;
    for (final marker in widget.markers) {
      if (marker.id == id) return marker;
    }
    return null;
  }

  /// UI 开关类选项序列化（creationParams 与动态更新共用）。
  Map<String, Object?> get _uiOptions => <String, Object?>{
    'trafficEnabled': widget.trafficEnabled,
    'touchPoiEnabled': widget.touchPoiEnabled,
    'buildingsEnabled': widget.buildingsEnabled,
    'labelsEnabled': widget.labelsEnabled,
    'compassEnabled': widget.compassEnabled,
    'scaleEnabled': widget.scaleEnabled,
  };

  /// 手势开关序列化（creationParams 与动态更新共用）。
  Map<String, Object?> get _gestures => <String, Object?>{
    'zoom': widget.zoomGesturesEnabled,
    'scroll': widget.scrollGesturesEnabled,
    'rotate': widget.rotateGesturesEnabled,
    'tilt': widget.tiltGesturesEnabled,
  };

  Map<String, Object?> get _creationParams => <String, Object?>{
    'mapId': _mapId,
    'initialCameraPosition': widget.initialCameraPosition.toJson(),
    'mapType': widget.mapType.toJson(),
    'language': widget.language.toJson(),
    'myLocationEnabled': widget.myLocationEnabled,
    if (widget.myLocationStyleOptions != null)
      'myLocationStyle': widget.myLocationStyleOptions!.toJson(),
    if (widget.customStyleOptions != null)
      'customStyle': widget.customStyleOptions!.toJson(),
    'minZoom': widget.minMaxZoomPreference.minZoom,
    'maxZoom': widget.minMaxZoomPreference.maxZoom,
    'limitBounds': widget.limitBounds?.toJson(),
    'uiOptions': _uiOptions,
    'gestures': _gestures,
    'markers': widget.markers.map((m) => m.toJson()).toList(),
    'polylines': widget.polylines.map((p) => p.toJson()).toList(),
    'polygons': widget.polygons.map((p) => p.toJson()).toList(),
    'circles': widget.circles.map((c) => c.toJson()).toList(),
  };

  @override
  Widget build(BuildContext context) {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        // Hybrid Composition：AMap 3D 地图基于 GLSurfaceView，
        // 必须用混合合成模式（initExpensiveAndroidView）保证渲染一致。
        // 首次布局后由 framework 自动触发 controller.create()。
        return PlatformViewLink(
          viewType: _viewType,
          surfaceFactory: (context, controller) => AndroidViewSurface(
            controller: controller as AndroidViewController,
            hitTestBehavior: PlatformViewHitTestBehavior.opaque,
            gestureRecognizers:
                widget.gestureRecognizers ?? _defaultGestureRecognizers,
          ),
          onCreatePlatformView: (params) {
            return PlatformViewsService.initExpensiveAndroidView(
              id: params.id,
              viewType: _viewType,
              layoutDirection: TextDirection.ltr,
              creationParams: _creationParams,
              creationParamsCodec: const StandardMessageCodec(),
            )
              ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
              ..addOnPlatformViewCreatedListener(
                (_) => _markPlatformViewCreated(),
              );
          },
        );
      case TargetPlatform.iOS:
        return UiKitView(
          viewType: _viewType,
          creationParams: _creationParams,
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: _onIosPlatformViewCreated,
          gestureRecognizers:
              widget.gestureRecognizers ??
              const <Factory<OneSequenceGestureRecognizer>>{},
        );
      default:
        return const Center(
          child: Text('amap_maps_flutter_qs 仅支持 Android / iOS'),
        );
    }
  }
}
