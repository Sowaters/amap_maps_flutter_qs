import 'package:amap_maps_flutter_qs/amap_maps_flutter_qs.dart';

/// ⚠️ 请替换为你自己的高德 Key（在高德开放平台申请）：
/// - AndroidKey：按「包名 + 签名 SHA1」申请
/// - iOSKey：按 BundleID 申请
///
/// 也可以不在这里传 key，改为 AndroidManifest meta-data /
/// iOS Info.plist 配置（见插件 README）。
const demoApiKey = AMapApiKey(
  androidKey: 'YOUR_ANDROID_KEY',
  iosKey: 'YOUR_IOS_KEY',
);

/// ⚠️ 隐私合规：
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
