part of 'overlay.dart';

/// 线覆盖物。
///
/// 构造与 [copyWith] 参数名对齐官方 `amap_flutter_map` 的 `Polyline`；
/// 默认值（宽度 10、颜色 `0xCCC4E0F0`、joinType bevel）也与官方一致。
class Polyline extends MapObject {
  /// 折线顶点（≥ 2 个）。
  final List<LatLng> points;

  /// 线宽（逻辑像素，Android dp / iOS point，≤ 0 时取 10）。
  final double width;

  /// 透明度 [0.0, 1.0]（超出范围自动截断）。
  final double alpha;

  /// 线颜色（设置 [customTexture] 后失效）。
  final Color color;

  /// 自定义纹理图片；设置后 [color] 失效。
  final BitmapDescriptor? customTexture;

  /// 是否为大地曲线。
  final bool geodesic;

  /// 虚线类型。
  final DashLineType dashLineType;

  /// 线头类型。
  final CapType capType;

  /// 连接点类型。
  final JoinType joinType;

  /// 点击回调。
  final void Function(String polylineId)? onTap;

  /// 平滑曲线折线：把稀疏控制点经 Catmull-Rom 样条加密后交给原生绘制。
  ///
  /// 这是「连线变曲线」的跨端通用做法 —— 原生折线在顶点之间只会画
  /// 直线段，本工厂先在 Dart 侧插值出密集中间点再创建普通 [Polyline]，
  /// Android / iOS 表现完全一致。见 [LineSmoothing.smoothCurve]。
  ///
  /// 注意：保存进 [points] 的是加密后的曲线顶点，原始控制点不再保留；
  /// 需要基于控制点做后续修改时，请自行保存控制点后重新调用本工厂。
  factory Polyline.smooth({
    required List<LatLng> points,
    int segmentsPerPair = 16,
    double tension = 1.0,
    bool closed = false,
    String? id,
    double width = 10.0,
    bool visible = true,
    bool geodesic = false,
    double alpha = 1.0,
    DashLineType dashLineType = DashLineType.none,
    CapType capType = CapType.butt,
    JoinType joinType = JoinType.bevel,
    BitmapDescriptor? customTexture,
    Color color = const Color(0xCCC4E0F0),
    void Function(String polylineId)? onTap,
    double zIndex = 0.0,
  }) {
    return Polyline(
      id: id,
      points: LineSmoothing.smoothCurve(
        points,
        segmentsPerPair: segmentsPerPair,
        tension: tension,
        closed: closed,
      ),
      width: width,
      visible: visible,
      geodesic: geodesic,
      alpha: alpha,
      dashLineType: dashLineType,
      capType: capType,
      joinType: joinType,
      customTexture: customTexture,
      color: color,
      onTap: onTap,
      zIndex: zIndex,
    );
  }

  Polyline({
    super.id,
    required this.points,
    double width = 10.0,
    super.visible = true,
    this.geodesic = false,
    double alpha = 1.0,
    this.dashLineType = DashLineType.none,
    this.capType = CapType.butt,
    this.joinType = JoinType.bevel,
    this.customTexture,
    this.color = const Color(0xCCC4E0F0),
    this.onTap,
    super.zIndex = 0.0,
  }) : assert(points.isNotEmpty, 'points must not be empty'),
       width = width <= 0 ? 10 : width,
       alpha = alpha < 0 ? 0 : (alpha > 1 ? 1 : alpha);

  /// 复制并替换指定字段（参数名对齐官方 `Param` 后缀约定）。
  Polyline copyWith({
    String? id,
    List<LatLng>? pointsParam,
    double? widthParam,
    bool? visibleParam,
    double? alphaParam,
    DashLineType? dashLineTypeParam,
    CapType? capTypeParam,
    JoinType? joinTypeParam,
    BitmapDescriptor? customTextureParam,
    Color? colorParam,
    bool? geodesicParam,
    void Function(String polylineId)? onTapParam,
    double? zIndexParam,
  }) => Polyline(
    id: id ?? this.id,
    points: pointsParam ?? points,
    width: widthParam ?? width,
    visible: visibleParam ?? visible,
    alpha: alphaParam ?? alpha,
    dashLineType: dashLineTypeParam ?? dashLineType,
    capType: capTypeParam ?? capType,
    joinType: joinTypeParam ?? joinType,
    customTexture: customTextureParam ?? customTexture,
    color: colorParam ?? color,
    geodesic: geodesicParam ?? geodesic,
    onTap: onTapParam ?? onTap,
    zIndex: zIndexParam ?? zIndex,
  );

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'points': points.map((p) => p.toJson()).toList(),
    'width': width,
    'visible': visible,
    'geodesic': geodesic,
    'alpha': alpha,
    'dashLineType': dashLineType.toJson(),
    'capType': capType.toJson(),
    'joinType': joinType.toJson(),
    'customTexture': customTexture?.toJson(),
    'color': color.toARGB32(),
    'zIndex': zIndex,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Polyline &&
          other.id == id &&
          _listEq(other.points, points) &&
          other.width == width &&
          other.visible == visible &&
          other.geodesic == geodesic &&
          other.alpha == alpha &&
          other.dashLineType == dashLineType &&
          other.capType == capType &&
          other.joinType == joinType &&
          other.customTexture == customTexture &&
          other.color == color &&
          other.zIndex == zIndex;

  @override
  int get hashCode => Object.hash(
    id,
    Object.hashAll(points),
    width,
    visible,
    geodesic,
    alpha,
    dashLineType,
    capType,
    joinType,
    customTexture,
    color,
    zIndex,
  );
}

bool _listEq(List<LatLng> a, List<LatLng> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
