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
import '../model/map_type.dart';
import '../model/min_max_zoom_preference.dart';
import '../model/my_location_style_options.dart';
import '../overlay/overlay.dart';

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
  late final MethodChannel _channel = MethodChannel(
    'amap_maps_flutter_qs/map#$_mapId',
  );

  /// 原生 PlatformView 是否已创建。
  ///
  /// iOS 的 UiKitView 与 Android 的 initExpensiveAndroidView 均为异步创建：
  /// build() 返回后原生 AMapPlatformView（即 `map#<mapId>` 通道 handler 的
  /// 注册方）稍后才存在。创建完成前任何通道下发都会 MissingPluginException。
  bool _platformViewCreated = false;

  /// 创建完成前暂存的通道调用，创建后按序冲刷（对齐 google_maps_flutter 做法）。
  final List<(String method, Object? args)> _pendingCalls = [];

  /// 通道下发统一入口：未创建前入队，创建后直接下发。
  Future<void> _invokeMapMethod(String method, [Object? args]) async {
    if (!_platformViewCreated) {
      _pendingCalls.add((method, args));
      return;
    }
    try {
      await _channel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      // 原生地图实例已销毁（如页面快速关闭 / dispose 后的迟到调用），静默丢弃
    }
  }

  /// PlatformView 创建完成（framework 侧 onPlatformViewCreated 与
  /// 原生 mapCreated 两条路径都会到达，幂等）。
  void _markPlatformViewCreated() {
    if (_platformViewCreated) return;
    _platformViewCreated = true;
    if (_pendingCalls.isEmpty) return;
    final calls = List.of(_pendingCalls);
    _pendingCalls.clear();
    for (final (method, args) in calls) {
      _invokeMapMethod(method, args);
    }
  }

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  @override
  void didUpdateWidget(AMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 覆盖物差量更新：仅下发增 / 删 / 改三部分（US-03）
    if (!identical(oldWidget.markers, widget.markers)) {
      final updates = MarkerUpdates.from(oldWidget.markers, widget.markers);
      if (!updates.isEmpty) {
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
    _pendingCalls.clear();
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'mapCreated':
        // 原生侧的兜底通知（framework onPlatformViewCreated 通常先到，幂等）
        _markPlatformViewCreated();
        widget.onMapCreated?.call(AMapController.createFor(_mapId));
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
        throw MissingPluginException('Unknown method ${call.method}');
    }
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
          onPlatformViewCreated: (_) => _markPlatformViewCreated(),
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
