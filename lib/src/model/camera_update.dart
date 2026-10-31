import 'dart:ui' show Offset;

import 'camera_position.dart';
import 'latlng.dart';
import 'latlng_bounds.dart';

/// 描述地图相机将要发生的变化。
///
/// 通过命名工厂构造（[newLatLng]、[newLatLngZoom] 等）创建，
/// 传给 [AMapController.moveCamera] / [AMapController.animateCamera]。
class CameraUpdate {
  final Map<String, Object?> _payload;

  const CameraUpdate._(this._payload);

  /// 移动中心点到 [latLng]。
  factory CameraUpdate.newLatLng(LatLng latLng) =>
      CameraUpdate._({'op': 'newLatLng', 'latLng': latLng.toJson()});

  /// 移动中心点到 [latLng] 并设置缩放级别 [zoom]。
  factory CameraUpdate.newLatLngZoom(LatLng latLng, double zoom) =>
      CameraUpdate._({
        'op': 'newLatLngZoom',
        'latLng': latLng.toJson(),
        'zoom': zoom,
      });

  /// 移动相机使 [bounds] 完全可见，四周保留 [padding] 像素边距。
  factory CameraUpdate.newLatLngBounds(LatLngBounds bounds, double padding) =>
      CameraUpdate._({
        'op': 'newLatLngBounds',
        'bounds': bounds.toJson(),
        'padding': padding,
      });

  /// 应用完整的相机状态 [cameraPosition]。
  factory CameraUpdate.newCameraPosition(CameraPosition cameraPosition) =>
      CameraUpdate._({
        'op': 'newCameraPosition',
        'cameraPosition': cameraPosition.toJson(),
      });

  /// 缩放到指定级别 [zoom]。
  factory CameraUpdate.zoomTo(double zoom) =>
      CameraUpdate._({'op': 'zoomTo', 'zoom': zoom});

  /// 在当前级别基础上缩放 [amount]（正为放大）。
  factory CameraUpdate.zoomBy(double amount) =>
      CameraUpdate._({'op': 'zoomBy', 'amount': amount});

  /// 缩放级别 +1（对齐官方 [CameraUpdate.zoomIn]）。
  factory CameraUpdate.zoomIn() => CameraUpdate._({'op': 'zoomIn'});

  /// 缩放级别 -1（对齐官方 [CameraUpdate.zoomOut]）。
  factory CameraUpdate.zoomOut() => CameraUpdate._({'op': 'zoomOut'});

  /// 在当前级别基础上缩放 [amount]，并以屏幕坐标 [focus]（像素）为不动点。
  factory CameraUpdate.zoomByFocus(double amount, Offset focus) =>
      CameraUpdate._({
        'op': 'zoomByFocus',
        'amount': amount,
        'focus': <double>[focus.dx, focus.dy],
      });

  /// 按像素滚动地图（dx 向右，dy 向下）。
  factory CameraUpdate.scrollBy(double dx, double dy) =>
      CameraUpdate._({'op': 'scrollBy', 'dx': dx, 'dy': dy});

  /// 序列化（用于平台通道传输）。
  Object toJson() => _payload;

  @override
  String toString() => 'CameraUpdate($_payload)';
}
