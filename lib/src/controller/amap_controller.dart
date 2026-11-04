import 'package:flutter/services.dart';

import '../model/camera_position.dart';
import '../model/camera_update.dart';
import '../model/custom_style_options.dart';
import '../model/latlng_bounds.dart';
import '../model/map_language.dart';
import '../model/map_type.dart';
import '../util/amap_logger.dart';

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
  ///
  /// [channel] 由调用方传入：Android 按插件 mapId 命名，iOS 按引擎 viewId
  /// 命名（两端一致的值）。缺省时按 mapId 推导（兼容旧调用）。
  static AMapController createFor(int mapId, {MethodChannel? channel}) =>
      AMapController._(
        mapId,
        channel ?? MethodChannel('amap_maps_flutter_qs/map#$mapId'),
      );

  @override
  String toString() => 'AMapController(mapId: $mapId)';

  /// 统一带日志的通道调用。
  Future<T?> _invoke<T>(String method, [Object? args]) {
    AMapLogger.d('map#$mapId -> $method ${args ?? ''}');
    return _channel.invokeMethod<T?>(method, args).catchError((Object e) {
      AMapLogger.w('map#$mapId -> $method 调用失败: $e');
      throw Error.throwWithStackTrace(e, StackTrace.current);
    });
  }

  /// 移动相机（签名对齐官方）。
  ///
  /// [animated] 控制是否执行动画移动；[duration] 为动画时长（毫秒，
  /// 默认 250，仅 [animated] 为 true 时生效）。
  Future<void> moveCamera(
    CameraUpdate cameraUpdate, {
    bool animated = true,
    int duration = 250,
  }) async {
    await _invoke<void>('map#moveCamera', <String, Object?>{
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
    await _invoke<void>('map#animateCamera', <String, Object?>{
      'update': cameraUpdate.toJson(),
      if (duration != null) 'durationMs': duration.inMilliseconds,
    });
  }

  /// 当前相机位置。
  Future<CameraPosition> getCameraPosition() async {
    final json = await _invoke<dynamic>('map#getCameraPosition');
    return CameraPosition.fromJson(json) ??
        (throw StateError('Invalid camera position payload: $json'));
  }

  /// 当前可视区域。
  Future<LatLngBounds> getVisibleRegion() async {
    final json = await _invoke<dynamic>('map#getVisibleRegion');
    return LatLngBounds.fromJson(json) ??
        (throw StateError('Invalid visible region payload: $json'));
  }

  /// 普通地图审图号（应用上架合规要求展示）。
  Future<String?> getMapContentApprovalNumber() async {
    return _invoke<String?>('map#getContentApprovalNumber');
  }

  /// 卫星地图审图号。
  Future<String?> getSatelliteImageApprovalNumber() async {
    return _invoke<String?>('map#getSatelliteApprovalNumber');
  }

  /// 地图截图（返回 PNG 字节）。
  Future<Uint8List?> takeSnapshot() async {
    return _invoke<Uint8List?>('map#takeSnapshot');
  }

  /// 设置地图类型。
  Future<void> setMapType(MapType mapType) async {
    await _invoke<void>('map#setMapType', mapType.toJson());
  }

  /// 设置地图语言（中文/英文）。
  ///
  /// SDK 限制：英文仅在标准地图类型下生效，且不能与自定义样式同用。
  Future<void> setLanguage(MapLanguage language) async {
    await _invoke<void>('map#setLanguage', language.toJson());
  }

  /// 动态设置自定义地图样式（无需重建地图）。
  ///
  /// 传 null 或 [CustomStyleOptions.enabled] = false 关闭自定义样式。
  /// 云端 ID / 本地二进制两种模式的取舍见 [CustomStyleOptions]。
  /// 注意：启用自定义样式后审图号查询将返回空（SDK 约定）。
  Future<void> setCustomStyle(CustomStyleOptions? options) async {
    await _invoke<void>('map#setCustomStyle', options?.toJson());
  }

  /// 显示指定 Marker 的气泡。
  ///
  /// 若该 Marker 使用了自定义气泡内容（`InfoWindow.content`），
  /// Android 端弹出的是自定义视图。
  Future<void> showInfoWindow(String markerId) async {
    await _invoke<void>('map#showInfoWindow', markerId);
  }

  /// 隐藏指定 Marker 的气泡。
  Future<void> hideInfoWindow(String markerId) async {
    await _invoke<void>('map#hideInfoWindow', markerId);
  }
}
