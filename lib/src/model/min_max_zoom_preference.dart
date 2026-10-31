/// 缩放级别范围限制（对齐基线插件同名类）。
///
/// [AMapWidget.minMaxZoomPreference] 使用；未显式限制的一端
/// 使用 [unbounded]。
class MinMaxZoomPreference {
  /// 最小缩放级别，null 表示不限制。
  final double? minZoom;

  /// 最大缩放级别，null 表示不限制。
  final double? maxZoom;

  const MinMaxZoomPreference(this.minZoom, this.maxZoom);

  /// 两端均不限制。
  static const MinMaxZoomPreference unbounded =
      MinMaxZoomPreference(null, null);

  /// 序列化（键与原生 creationParams 既有约定一致）。
  Map<String, Object?> toJson() => <String, Object?>{
    'min': minZoom,
    'max': maxZoom,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MinMaxZoomPreference &&
          other.minZoom == minZoom &&
          other.maxZoom == maxZoom;

  @override
  int get hashCode => Object.hash(minZoom, maxZoom);

  @override
  String toString() => 'MinMaxZoomPreference(min: $minZoom, max: $maxZoom)';
}
