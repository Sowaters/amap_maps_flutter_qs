import 'package:amap_maps_flutter_qs/amap_maps_flutter_qs.dart';

/// ⚠️ Key 不入库（避免泄漏到 pub.dev），运行时经 --dart-define 注入：
///
/// ```bash
/// flutter run \
///   --dart-define=AMAP_ANDROID_KEY=<你的AndroidKey> \
///   --dart-define=AMAP_IOS_KEY=<你的iOSKey>
/// ```
///
/// Key 在[高德开放平台](https://console.amap.com)申请：
/// - AndroidKey：按「包名 + 签名 SHA1」
/// - iOSKey：按 BundleID
///
/// 也可以不在这里传 key，改为 AndroidManifest meta-data /
/// iOS Info.plist 配置（见插件 README）。
///
/// 注意：不注入有效 Key 时地图渲染受限（iOS 端部分 SDK 版本
/// MAMapView 会创建失败，Android 端定位/检索等功能不可用）；
/// 正式使用必须在用户同意隐私政策后传入真实合规状态。
const _androidKey = String.fromEnvironment('AMAP_ANDROID_KEY');
const _iosKey = String.fromEnvironment('AMAP_IOS_KEY');

const demoApiKey = AMapApiKey(androidKey: _androidKey, iosKey: _iosKey);

/// ⚠️ 隐私合规：˚
/// 真实 App 中必须先展示隐私弹窗，用户同意后将状态同步给 SDK。
/// Demo 为演示方便直接声明「已同意」，勿照抄。
const demoPrivacy = AMapPrivacyStatement(
  hasContains: true,
  hasShow: true,
  hasAgree: true,
);

// ---- Demo 通用坐标 ----

/// 北京天安门。
const beijingCenter = LatLng(39.909187, 116.397451);

/// 上海人民广场。
const shanghaiCenter = LatLng(31.230416, 121.473701);

/// 北京五环范围（相机边界演示用）。
final beijingBounds = LatLngBounds(
  southwest: LatLng(39.75, 116.25),
  northeast: LatLng(40.05, 116.65),
);

/// 初始相机：北京，zoom 12。
const initialCamera = CameraPosition(target: beijingCenter, zoom: 12);
