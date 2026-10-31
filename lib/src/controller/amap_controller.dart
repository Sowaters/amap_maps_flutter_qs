import 'package:flutter/services.dart';

import '../model/camera_position.dart';
import '../model/camera_update.dart';
import '../model/latlng_bounds.dart';
import '../model/map_type.dart';

/// 地图通信中心：控制相机、查询地图状态。
///
/// 通过 [AMapWidget.onMapCreated] 回调获得实例。生命周期与对应的
/// [AMapWidget] 绑定，Widget 销毁后实例随之失效。
class AMapController {
  /// 本实例对应的地图 id（与 [AMapWidget] 实例一一对应）。
  final int mapId;

  final MethodChannel _channel;

  AMapController._(this.mapId, this._channel);

  /// 由 [AMapWidget] 内部创建。
  static AMapController createFor(int mapId) =>
      AMapController._(mapId, MethodChannel('amap_maps_flutter_qs/map#$mapId'));

  @override
  String toString() => 'AMapController(mapId: $mapId)';

  /// 移动相机（签名对齐官方）。
  ///
  /// [animated] 控制是否执行动画移动；[duration] 为动画时长（毫秒，
  /// 默认 250，仅 [animated] 为 true 时生效）。
  Future<void> moveCamera(
    CameraUpdate cameraUpdate, {
    bool animated = true,
    int duration = 250,
  }) async {
    await _channel.invokeMethod<void>('map#moveCamera', <String, Object?>{
      'update': cameraUpdate.toJson(),
      'animated': animated,
      'durationMs': duration,
    });
  }

  /// 动画移动相机。
  @Deprecated('Use moveCamera(cameraUpdate, animated: true) instead')
  Future<void> animateCamera(
    CameraUpdate cameraUpdate, {
    Duration? duration,
  }) async {
    await _channel.invokeMethod<void>('map#animateCamera', <String, Object?>{
      'update': cameraUpdate.toJson(),
      if (duration != null) 'durationMs': duration.inMilliseconds,
    });
  }

  /// 当前相机位置。
  Future<CameraPosition> getCameraPosition() async {
    final json = await _channel.invokeMethod<dynamic>('map#getCameraPosition');
    return CameraPosition.fromJson(json) ??
        (throw StateError('Invalid camera position payload: $json'));
  }

  /// 当前可视区域。
  Future<LatLngBounds> getVisibleRegion() async {
    final json = await _channel.invokeMethod<dynamic>('map#getVisibleRegion');
    return LatLngBounds.fromJson(json) ??
        (throw StateError('Invalid visible region payload: $json'));
  }

  /// 普通地图审图号（应用上架合规要求展示）。
  Future<String?> getMapContentApprovalNumber() async {
    return _channel.invokeMethod<String?>('map#getContentApprovalNumber');
  }

  /// 卫星地图审图号。
  Future<String?> getSatelliteImageApprovalNumber() async {
    return _channel.invokeMethod<String?>('map#getSatelliteApprovalNumber');
  }

  /// 地图截图（返回 PNG 字节）。
  Future<Uint8List?> takeSnapshot() async {
    return _channel.invokeMethod<Uint8List?>('map#takeSnapshot');
  }

  /// 设置地图类型。
  Future<void> setMapType(MapType mapType) async {
    await _channel.invokeMethod<void>('map#setMapType', mapType.toJson());
  }

  /// 显示指定 Marker 的气泡。
  ///
  /// 若该 Marker 使用了自定义气泡内容（`InfoWindow.content`），
  /// Android 端弹出的是自定义视图。
  Future<void> showInfoWindow(String markerId) async {
    await _channel.invokeMethod<void>('map#showInfoWindow', markerId);
  }

  /// 隐藏指定 Marker 的气泡。
  Future<void> hideInfoWindow(String markerId) async {
    await _channel.invokeMethod<void>('map#hideInfoWindow', markerId);
  }
}
