part of 'overlay.dart';

/// 圆形覆盖物（基线官方插件缺失，本插件补齐；
/// 参数命名风格与官方 `Param` 后缀约定保持一致）。
class Circle extends MapObject {
  /// 圆心。
  final LatLng center;

  /// 半径（米）。
  final double radius;

  /// 边框线宽（逻辑像素，≤ 0 时取 10）。
  final double strokeWidth;

  /// 边框颜色。
  final Color strokeColor;

  /// 填充颜色。
  final Color fillColor;

  /// 点击回调。
  final void Function(String circleId)? onTap;

  Circle({
    super.id,
    required this.center,
    required this.radius,
    double strokeWidth = 10.0,
    this.strokeColor = const Color(0xCC00BFFF),
    this.fillColor = const Color(0xC487CEFA),
    this.onTap,
    super.visible = true,
    super.zIndex = 0.0,
  }) : strokeWidth = strokeWidth <= 0 ? 10 : strokeWidth;

  /// 复制并替换指定字段（参数名对齐官方 `Param` 后缀约定）。
  Circle copyWith({
    LatLng? centerParam,
    double? radiusParam,
    double? strokeWidthParam,
    Color? strokeColorParam,
    Color? fillColorParam,
    bool? visibleParam,
    double? zIndexParam,
  }) => Circle(
    id: id,
    center: centerParam ?? center,
    radius: radiusParam ?? radius,
    strokeWidth: strokeWidthParam ?? strokeWidth,
    strokeColor: strokeColorParam ?? strokeColor,
    fillColor: fillColorParam ?? fillColor,
    onTap: onTap,
    visible: visibleParam ?? visible,
    zIndex: zIndexParam ?? zIndex,
  );

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'center': center.toJson(),
    'radius': radius,
    'strokeWidth': strokeWidth,
    'strokeColor': strokeColor.toARGB32(),
    'fillColor': fillColor.toARGB32(),
    'visible': visible,
    'zIndex': zIndex,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Circle &&
          other.id == id &&
          other.center == center &&
          other.radius == radius &&
          other.strokeWidth == strokeWidth &&
          other.strokeColor == strokeColor &&
          other.fillColor == fillColor &&
          other.visible == visible &&
          other.zIndex == zIndex;

  @override
  int get hashCode => Object.hash(
    id,
    center,
    radius,
    strokeWidth,
    strokeColor,
    fillColor,
    visible,
    zIndex,
  );
}
