import MAMapKit
import Flutter
import UIKit

/// 插件入口：注册主通道（init / 隐私合规）与地图 PlatformView。
public class AmapMapsFlutterQsPlugin: NSObject, FlutterPlugin {
  static let viewType = "amap_maps_flutter_qs/map"
  static let mainChannelName = "amap_maps_flutter_qs"

  public static func register(with registrar: FlutterPluginRegistrar) {
    AMapLog.d("register：注册主通道 \(mainChannelName) 与 PlatformViewFactory \(viewType)")
    let channel = FlutterMethodChannel(
      name: mainChannelName, binaryMessenger: registrar.messenger())
    let instance = AmapMapsFlutterQsPlugin(messenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: channel)

    let factory = AMapPlatformViewFactory(messenger: registrar.messenger())
    registrar.register(
      factory,
      withId: viewType,
      gestureRecognizersBlockingPolicy:
        FlutterPlatformViewGestureRecognizersBlockingPolicyWaitUntilTouchesEnded)
  }

  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]

    switch call.method {
    case "init":
      initialize(args?["apiKey"] as? [String: Any], privacy: args?["privacy"] as? [String: Any])
      result(nil)

    case "updatePrivacyShow":
      let privacy = args ?? [:]
      let showStatus: AMapPrivacyShowStatus =
        (privacy["hasShow"] as? Bool) == true ? .didShow : .notShow
      let infoStatus: AMapPrivacyInfoStatus =
        (privacy["hasContains"] as? Bool) == true ? .didContain : .notContain
      MAMapView.updatePrivacyShow(showStatus, privacyInfo: infoStatus)
      result(nil)

    case "updatePrivacyAgree":
      let privacy = args ?? [:]
      let agreeStatus: AMapPrivacyAgreeStatus =
        (privacy["hasAgree"] as? Bool) == true ? .didAgree : .notAgree
      MAMapView.updatePrivacyAgree(agreeStatus)
      result(nil)

    case "map#attach":
      // 握手：creationParams 未能随平台视图 create 下发时（引擎 args=nil），
      // Dart 在 onPlatformViewCreated 后经主通道补送参数，原生应用初始配置
      // 并回发 mapCreated。返回 viewId（已应用参数）；-2 = create 时参数已
      // 正常送达；-3 = 注册表中无此视图（已 dispose）。
      let attachArgs = args ?? [:]
      let viewId = (attachArgs["viewId"] as? NSNumber)?.int64Value ?? -1
      let params = attachArgs["params"] as? [String: Any] ?? [:]
      result(AMapPlatformView.attach(viewId: viewId, creationParams: params))

    case "debug#listMaps":
      // 诊断探针：返回当前已注册的地图通道名列表。
      // Dart 端在 per-map 通道 MissingPluginException 时自动调用。
      result(["maps": AMapPlatformView.liveChannelNames])

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func initialize(_ apiKey: [String: Any]?, privacy: [String: Any]?) {
    // iOS Key：程序化注入（AMapServices 单例，全局生效）
    if let iosKey = apiKey?["iosKey"] as? String, !iosKey.isEmpty, iosKey != "YOUR_IOS_KEY" {
      AMapServices.shared().apiKey = iosKey
      AMapLog.d("init：iOS ApiKey 已注入")
    } else {
      AMapLog.d("init：iOS ApiKey 未配置或为占位符（地图可能仅显示空白网格，定位/检索等功能不可用）")
    }
    AMapServices.shared().enableHTTPS = true
    // 注意：不要开启 MAMapView.metalEnabled！
    // 实测（Flutter 3.47 Impeller + MAMapKit 11.2 + iOS 26 真机）：Metal 渲染器
    // 的瓦片层无法合成进 Flutter 平台视图（纯蓝背景、logo/比例尺正常、
    // tileLoad success=true、MAMapMetalRender 子视图正常）。SDK 默认渲染器
    // （OpenGL）在平台视图合成下工作正常。

    // 隐私合规（SDK 8.1.0+）：必须在任何 MAMapView 实例化之前调用
    let showStatus: AMapPrivacyShowStatus =
      (privacy?["hasShow"] as? Bool) == true ? .didShow : .notShow
    let infoStatus: AMapPrivacyInfoStatus =
      (privacy?["hasContains"] as? Bool) == true ? .didContain : .notContain
    let agreeStatus: AMapPrivacyAgreeStatus =
      (privacy?["hasAgree"] as? Bool) == true ? .didAgree : .notAgree
    MAMapView.updatePrivacyShow(showStatus, privacyInfo: infoStatus)
    MAMapView.updatePrivacyAgree(agreeStatus)
    AMapLog.d(
      "init：隐私合规 show=\(privacy?["hasShow"] ?? false) contains=\(privacy?["hasContains"] ?? false)"
        + " agree=\(privacy?["hasAgree"] ?? false)"
        + "（任一为 false 时 SDK 功能将被限制，地图可能只渲染底图）")
  }
}
