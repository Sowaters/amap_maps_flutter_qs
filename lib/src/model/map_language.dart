/// 地图语言。
///
/// 注意（两端 SDK 共同限制）：英文模式仅在标准地图类型下生效，
/// 且不能与自定义地图样式同时使用。
enum MapLanguage {
  /// 中文。
  chinese,

  /// 英文。
  english;

  /// 原生 SDK 对应的枚举值（iOS mapLanguage：0=中文 / 1=英文；
  /// Android setMapLanguage：AMap.CHINESE / AMap.ENGLISH）。
  int get nativeCode => switch (this) {
    MapLanguage.chinese => 0,
    MapLanguage.english => 1,
  };

  /// 从通道消息反序列化。
  static MapLanguage? fromJson(Object? json) {
    if (json is int) {
      return MapLanguage.values.firstWhere(
        (l) => l.nativeCode == json,
        orElse: () => MapLanguage.chinese,
      );
    }
    return null;
  }

  /// 序列化（传原生枚举值）。
  Object toJson() => nativeCode;
}
