import 'package:flutter/services.dart';

import 'amap_api_key.dart';
import 'amap_privacy_statement.dart';
import '../util/amap_logger.dart';

/// 插件全局初始化入口。
///
/// 必须在创建任何 [AMapWidget] 之前调用（推荐放在 `main()` 或首个页面
/// `initState` 中）。原生侧会在此完成：ApiKey 注入、隐私合规状态同步。
///
/// 示例：
/// ```dart
/// Future<void> main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await AMapInitializer.init(
///     apiKey: const AMapApiKey(
///       androidKey: '你的AndroidKey',
///       iosKey: '你的iOSKey',
///     ),
///     privacyStatement: const AMapPrivacyStatement(
///       hasContains: true,
///       hasShow: true,
///       hasAgree: true, // 应在用户真实同意后再置 true
///     ),
///   );
///   runApp(const MyApp());
/// }
/// ```
abstract final class AMapInitializer {
  static const MethodChannel _channel = MethodChannel('amap_maps_flutter_qs');

  static bool _initialized = false;

  /// 是否已完成初始化。
  static bool get isInitialized => _initialized;

  /// 初始化 SDK：注入 ApiKey 并同步隐私声明状态。
  ///
  /// Android 的 key 也可以只在 `AndroidManifest.xml` 配置
  /// （`com.amap.api.v2.apikey` meta-data），此时 [apiKey] 传空串即可。
  static Future<void> init({
    required AMapApiKey apiKey,
    AMapPrivacyStatement? privacyStatement,
  }) async {
    final privacy = privacyStatement ?? const AMapPrivacyStatement();
    AMapLogger.d(
      'init 下发: iosKey=${apiKey.iosKey.isEmpty || apiKey.iosKey == 'YOUR_IOS_KEY' ? "（未配置/占位符！）" : "已配置"}'
      ' privacy(contains=${privacy.hasContains}, show=${privacy.hasShow}, agree=${privacy.hasAgree})',
    );
    await _channel.invokeMethod<void>('init', <String, Object?>{
      'apiKey': apiKey.toJson(),
      'privacy': privacy.toJson(),
    });
    _initialized = true;
    AMapLogger.d('init 完成');
  }

  /// 同步「隐私弹窗展示」状态（可在 init 之后、用户弹窗行为变化时调用）。
  static Future<void> updatePrivacyShow(AMapPrivacyStatement statement) {
    return _channel.invokeMethod<void>('updatePrivacyShow', statement.toJson());
  }

  /// 同步「用户同意隐私协议」状态。用户同意后必须调用。
  static Future<void> updatePrivacyAgree(AMapPrivacyStatement statement) {
    return _channel.invokeMethod<void>(
      'updatePrivacyAgree',
      statement.toJson(),
    );
  }
}
