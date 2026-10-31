/// 线头类型。
enum CapType {
  butt,
  round,
  square,
  arrow;

  /// 通道序列化。
  Object toJson() => name;
}

/// 线段连接点类型。
enum JoinType {
  bevel,
  miter,
  round;

  /// 通道序列化。
  Object toJson() => name;
}

/// 虚线类型。
enum DashLineType {
  none,
  dash,
  dashDot,
  dot;

  /// 通道序列化。
  Object toJson() => name;
}
