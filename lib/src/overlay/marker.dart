part of 'overlay.dart';

/// 点覆盖物。
///
/// 构造与 [copyWith] 参数名对齐官方 `amap_flutter_map` 的 `Marker`
/// （`iconParam` / `positionParam` 等 `Param` 后缀约定）。
class Marker extends MapObject {
  /// 透明度 [0.0, 1.0]（超出范围自动截断）。
  final double alpha;

  /// 图标锚点，(0,0) 为左上角，(1,1) 为右下角，默认 (0.5, 1.0) 底部中心。
  ///
  /// 超出 [0, 1] 范围时回退为默认值（与官方行为一致）。
  final Offset anchor;

  /// 是否可点击（预留字段，原生端暂未区分，见 MIGRATION.md）。
  final bool clickable;

  /// 是否可拖拽。
  final bool draggable;

  /// 是否平贴地图（随地图旋转/倾斜），否则始终面向屏幕。
  ///
  /// 官方 3.0.0 未提供该属性，本插件作为超集保留。
  final bool flat;

  /// 图标。
  final BitmapDescriptor icon;

  /// 是否允许显示气泡；为 false 时点击 Marker 永远不弹气泡。
  final bool infoWindowEnable;

  /// 气泡。
  final InfoWindow infoWindow;

  /// 坐标。
  final LatLng position;

  /// 旋转角度（度，平面模式下从正北顺时针，绕锚点旋转）。
  final double rotation;

  /// 点击回调。
  final void Function(String markerId)? onTap;

  /// 拖拽结束回调（位置经 [AMapWidget.onMarkerDragEnd] 二次分发）。
  final void Function(String markerId, LatLng endPosition)? onDragEnd;

  Marker({
    super.id,
    required this.position,
    double alpha = 1.0,
    Offset anchor = const Offset(0.5, 1.0),
    this.clickable = true,
    this.draggable = false,
    this.flat = false,
    this.icon = BitmapDescriptor.defaultMarker,
    this.infoWindowEnable = true,
    this.infoWindow = InfoWindow.noText,
    this.rotation = 0.0,
    this.onTap,
    this.onDragEnd,
    super.visible = true,
    super.zIndex = 0.0,
  }) : alpha = alpha < 0 ? 0 : (alpha > 1 ? 1 : alpha),
       anchor =
           (anchor.dx < 0 || anchor.dx > 1 || anchor.dy < 0 || anchor.dy > 1)
           ? const Offset(0.5, 1.0)
           : anchor;

  /// 复制并替换指定字段。
  ///
  /// 参数名对齐官方 `Param` 后缀约定；`id` 默认沿用原值
  /// （官方 copyWith 不允许改 id）。
  Marker copyWith({
    String? id,
    double? alphaParam,
    Offset? anchorParam,
    bool? clickableParam,
    bool? draggableParam,
    BitmapDescriptor? iconParam,
    bool? infoWindowEnableParam,
    InfoWindow? infoWindowParam,
    LatLng? positionParam,
    double? rotationParam,
    bool? visibleParam,
    double? zIndexParam,
    bool? flatParam,
    void Function(String markerId)? onTapParam,
    void Function(String markerId, LatLng endPosition)? onDragEndParam,
  }) => Marker(
    id: id ?? this.id,
    alpha: alphaParam ?? alpha,
    anchor: anchorParam ?? anchor,
    clickable: clickableParam ?? clickable,
    draggable: draggableParam ?? draggable,
    icon: iconParam ?? icon,
    infoWindowEnable: infoWindowEnableParam ?? infoWindowEnable,
    infoWindow: infoWindowParam ?? infoWindow,
    position: positionParam ?? position,
    rotation: rotationParam ?? rotation,
    visible: visibleParam ?? visible,
    zIndex: zIndexParam ?? zIndex,
    flat: flatParam ?? flat,
    onTap: onTapParam ?? onTap,
    onDragEnd: onDragEndParam ?? onDragEnd,
  );

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'alpha': alpha,
    'anchor': <double>[anchor.dx, anchor.dy],
    'clickable': clickable,
    'draggable': draggable,
    'flat': flat,
    'icon': icon.toJson(),
    'infoWindowEnable': infoWindowEnable,
    'infoWindow': infoWindow.toJson(),
    'position': position.toJson(),
    'rotation': rotation,
    'visible': visible,
    'zIndex': zIndex,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Marker &&
          other.id == id &&
          other.alpha == alpha &&
          other.anchor == anchor &&
          other.clickable == clickable &&
          other.draggable == draggable &&
          other.flat == flat &&
          other.icon == icon &&
          other.infoWindowEnable == infoWindowEnable &&
          other.infoWindow.title == infoWindow.title &&
          other.infoWindow.snippet == infoWindow.snippet &&
          other.infoWindow.content == infoWindow.content &&
          other.infoWindow.show == infoWindow.show &&
          other.position == position &&
          other.rotation == rotation &&
          other.visible == visible &&
          other.zIndex == zIndex;

  @override
  int get hashCode => Object.hash(
    id,
    alpha,
    anchor,
    clickable,
    draggable,
    flat,
    icon,
    infoWindowEnable,
    infoWindow.title,
    infoWindow.snippet,
    infoWindow.content,
    infoWindow.show,
    position,
    rotation,
    visible,
    zIndex,
  );
}
