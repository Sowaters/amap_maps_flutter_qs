import 'dart:typed_data';

/// 地图自定义样式。
///
/// 构造签名对齐官方 `amap_flutter_map` 的 `CustomStyleOptions`：
/// 首位位置参数 [enabled] 控制是否开启自定义地图；[styleData] /
/// [styleExtraData] 对应高德控制台下载的自定义地图压缩包中
/// `style.data` / `style_extra.data` 的二进制数据（本地样式模式）。
///
/// [customStyleId] 为本插件扩展：云端样式 ID 模式（在开放平台
/// 「自定义地图」控制台创建），两种模式二选一，同时设置时
/// 本地二进制数据优先。
class CustomStyleOptions {
  /// 开关项，是否开启自定义地图。
  final bool enabled;

  /// 自定义样式二进制数据（style.data 内容）。
  final Uint8List? styleData;

  /// 自定义扩展样式二进制数据（style_extra.data 内容）。
  final Uint8List? styleExtraData;

  /// 云端样式 ID（本插件扩展，官方无对应参数）。
  final String? customStyleId;

  const CustomStyleOptions(
    this.enabled, {
    this.styleData,
    this.styleExtraData,
    this.customStyleId,
  });

  /// 是否配置了样式。
  bool get hasStyle =>
      (styleData != null && styleData!.isNotEmpty) ||
      (customStyleId != null && customStyleId!.isNotEmpty);

  /// 序列化。
  Map<String, Object?> toJson() => <String, Object?>{
    'enabled': enabled,
    'styleData': styleData,
    'styleExtraData': styleExtraData,
    'customStyleId': customStyleId,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CustomStyleOptions &&
          other.enabled == enabled &&
          _bytesEquals(other.styleData, styleData) &&
          _bytesEquals(other.styleExtraData, styleExtraData) &&
          other.customStyleId == customStyleId;

  @override
  int get hashCode => Object.hash(
    enabled,
    styleData?.length,
    styleExtraData?.length,
    customStyleId,
  );

  @override
  String toString() =>
      'CustomStyleOptions($enabled, customStyleId: $customStyleId)';

  static bool _bytesEquals(Uint8List? a, Uint8List? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
