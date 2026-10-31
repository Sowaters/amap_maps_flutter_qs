import AMap3DMap
import Flutter
import UIKit

/// 插件入口：注册主通道（init / 隐私合规）与地图 PlatformView。
public class AmapMapsFlutterQsPlugin: NSObject, FlutterPlugin {
  static let viewType = "amap_maps_flutter_qs/map"
  static let mainChannelName = "amap_maps_flutter_qs"

  public static func register(with registrar: FlutterPluginRegistrar) {
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

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func initialize(_ apiKey: [String: Any]?, privacy: [String: Any]?) {
    // iOS Key：程序化注入（AMapServices 单例，全局生效）
    if let iosKey = apiKey?["iosKey"] as? String, !iosKey.isEmpty, iosKey != "YOUR_IOS_KEY" {
      AMapServices.shared().apiKey = iosKey
    }
    AMapServices.shared().enableHTTPS = true

    // 隐私合规（SDK 8.1.0+）：必须在任何 MAMapView 实例化之前调用
    let showStatus: AMapPrivacyShowStatus =
      (privacy?["hasShow"] as? Bool) == true ? .didShow : .notShow
    let infoStatus: AMapPrivacyInfoStatus =
      (privacy?["hasContains"] as? Bool) == true ? .didContain : .notContain
    let agreeStatus: AMapPrivacyAgreeStatus =
      (privacy?["hasAgree"] as? Bool) == true ? .didAgree : .notAgree
    MAMapView.updatePrivacyShow(showStatus, privacyInfo: infoStatus)
    MAMapView.updatePrivacyAgree(agreeStatus)
  }
}
