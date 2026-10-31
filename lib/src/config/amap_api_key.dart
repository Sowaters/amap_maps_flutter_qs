/// 高德开放平台 ApiKey 配置。
///
/// Android 端 key 也可通过 `AndroidManifest.xml` 的
/// `com.amap.api.v2.apikey` meta-data 配置（Dart 侧配置优先）。
class AMapApiKey {
  /// Android 平台 Key（在高德控制台按「包名 + SHA1」申请）。
  final String androidKey;

  /// iOS 平台 Key（在高德控制台按 BundleID 申请）。
  final String iosKey;

  const AMapApiKey({required this.androidKey, required this.iosKey});

  /// 序列化。
  Map<String, Object?> toJson() => <String, Object?>{
    'androidKey': androidKey,
    'iosKey': iosKey,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AMapApiKey &&
          other.androidKey == androidKey &&
          other.iosKey == iosKey;

  @override
  int get hashCode => Object.hash(androidKey, iosKey);

  @override
  String toString() =>
      'AMapApiKey(androidKey: ${_mask(androidKey)}, iosKey: ${_mask(iosKey)})';

  static String _mask(String key) =>
      key.length <= 8 ? '***' : '${key.substring(0, 4)}***';
}
