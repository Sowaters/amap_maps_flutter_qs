/// 地图类型。
enum MapType {
  /// 普通地图（矢量）。
  normal,

  /// 卫星地图。
  satellite,

  /// 夜间地图。
  night,

  /// 导航地图。
  navi,

  /// 公交地图。
  bus;

  /// 原生 SDK 对应的枚举值。
  int get nativeCode => switch (this) {
    MapType.normal => 1,
    MapType.satellite => 2,
    MapType.night => 3,
    MapType.navi => 4,
    MapType.bus => 5,
  };

  /// 从通道消息反序列化。
  static MapType? fromJson(Object? json) {
    if (json is int) {
      return MapType.values.firstWhere(
        (t) => t.nativeCode == json,
        orElse: () => MapType.normal,
      );
    }
    return null;
  }

  /// 序列化（传原生枚举值）。
  Object toJson() => nativeCode;
}
