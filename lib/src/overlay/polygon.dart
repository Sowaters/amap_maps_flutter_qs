part of 'overlay.dart';

/// 面覆盖物。
///
/// 构造与 [copyWith] 参数名对齐官方 `amap_flutter_map` 的 `Polygon`；
/// 默认值（边框 0xCC00BFFF、填充 0xC487CEFA、joinType bevel）与官方一致。
/// [holes] / [hollow] 为本插件扩展（官方无孔洞与镂空）。
class Polygon extends MapObject {
  /// 多边形顶点（≥ 3 个）。
  final List<LatLng> points;

  /// 孔洞环列表（每个环为独立顶点列表，≥ 3 个顶点，方向不限）。
  ///
  /// 典型来源：[GeometryUtil] 几何运算产生的带孔结果。
  final List<List<LatLng>> holes;

  /// 边框线宽（逻辑像素，同 Android dp / iOS point，≤ 0 时取 10）。
  final double strokeWidth;

  /// 边框颜色。
  final Color strokeColor;

  /// 填充颜色。
  final Color fillColor;

  /// 是否镂空（仅描边）。
  final bool hollow;

  /// 连接点类型（与官方一致：仅初始化时设置一次，copy 不支持修改）。
  final JoinType joinType;

  /// 点击回调。
  final void Function(String polygonId)? onTap;

  Polygon({
    super.id,
    required this.points,
    this.holes = const <List<LatLng>>[],
    double strokeWidth = 10.0,
    this.strokeColor = const Color(0xCC00BFFF),
    this.fillColor = const Color(0xC487CEFA),
    this.hollow = false,
    this.joinType = JoinType.bevel,
    this.onTap,
    super.visible = true,
    super.zIndex = 0.0,
  }) : strokeWidth = strokeWidth <= 0 ? 10 : strokeWidth;

  /// 复制并替换指定字段（参数名对齐官方 `Param` 后缀约定；
  /// [joinType] 与官方一致不可通过 copy 修改）。
  Polygon copyWith({
    List<LatLng>? pointsParam,
    double? strokeWidthParam,
    Color? strokeColorParam,
    Color? fillColorParam,
    bool? visibleParam,
    double? zIndexParam,
    List<List<LatLng>>? holesParam,
    bool? hollowParam,
  }) => Polygon(
    id: id,
    points: pointsParam ?? points,
    holes: holesParam ?? holes,
    strokeWidth: strokeWidthParam ?? strokeWidth,
    strokeColor: strokeColorParam ?? strokeColor,
    fillColor: fillColorParam ?? fillColor,
    hollow: hollowParam ?? hollow,
    joinType: joinType,
    onTap: onTap,
    visible: visibleParam ?? visible,
    zIndex: zIndexParam ?? zIndex,
  );

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'points': points.map((p) => p.toJson()).toList(),
    'holes': holes.map((h) => h.map((p) => p.toJson()).toList()).toList(),
    'strokeWidth': strokeWidth,
    'strokeColor': strokeColor.toARGB32(),
    'fillColor': fillColor.toARGB32(),
    'hollow': hollow,
    'joinType': joinType.toJson(),
    'visible': visible,
    'zIndex': zIndex,
  };

  int get _holesHash =>
      Object.hashAll(holes.map(Object.hashAll).toList(growable: false));

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Polygon &&
          other.id == id &&
          Object.hashAll(other.points) == Object.hashAll(points) &&
          other._holesHash == _holesHash &&
          other.strokeWidth == strokeWidth &&
          other.strokeColor == strokeColor &&
          other.fillColor == fillColor &&
          other.hollow == hollow &&
          other.visible == visible &&
          other.zIndex == zIndex;

  @override
  int get hashCode => Object.hash(
    id,
    Object.hashAll(points),
    _holesHash,
    strokeWidth,
    strokeColor,
    fillColor,
    hollow,
    visible,
    zIndex,
  );
}
