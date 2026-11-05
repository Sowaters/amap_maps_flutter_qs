import MAMapKit
import CryptoKit
import Flutter
import Foundation
import UIKit

/// 原生端日志工具：统一 `[AMapQS]` 前缀，Xcode 控制台直接过滤。
///
/// Debug 构建默认开启，Release 默认关闭。排查「地图只显示、其他功能不生效」
/// 时重点看 guard 失败日志（覆盖物被静默丢弃的原因）。
enum AMapLog {
  /// 日志开关，可在运行时动态调整；默认仅 Debug 构建开启。
  static var enabled: Bool = {
    #if DEBUG
    return true
    #else
    return false
    #endif
  }()

  /// 用 print（stdout）而非 NSLog：实测真机上 flutter run 控制台
  /// 不回显插件 pod 的 NSLog，但 stdout 一定可见。
  static func d(_ message: String) {
    guard enabled else { return }
    print("[AMapQS] \(message)")
    fflush(stdout)
  }
}

/// 地图 PlatformView 工厂。creationParams 由 Dart 侧 AMapWidget 传入。
public class AMapPlatformViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  /// 引擎用它解码 Dart 发来的 creationParams。
  /// 签名对齐官方文档（FlutterMessageCodec & NSObjectProtocol）。
  /// 若引擎未调用本方法或解码失败，create 的 args 将为 nil → 触发 Dart 侧
  /// map#attach 兜底握手。
  public func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    AMapLog.d("createArgsCodec 被调用（引擎正在解码 creationParams）")
    return FlutterStandardMessageCodec.sharedInstance()
  }

  public func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    let params = args as? [String: Any] ?? [:]
    AMapLog.d(
      "factory create viewId=\(viewId) args 类型=\(type(of: args))"
        + (params.isEmpty ? "（空！参数未送达）" : " params键=\(params.keys.sorted())"))
    return AMapPlatformView(
      frame: frame, viewIdentifier: viewId, messenger: messenger, creationParams: params)
  }
}

// MARK: - 携带业务数据的注解 / 覆盖物子类（用于 id 反查）

final class QsMarker: MAPointAnnotation {
  let customId: String
  let json: [String: Any]
  init(customId: String, json: [String: Any]) {
    self.customId = customId
    self.json = json
    super.init()
  }
}

final class QsPolyline: MAPolyline {
  let customId: String
  let json: [String: Any]
  init(customId: String, json: [String: Any]) {
    self.customId = customId
    self.json = json
    super.init()
  }
}

final class QsPolygon: MAPolygon {
  let customId: String
  let json: [String: Any]
  init(
    customId: String,
    json: [String: Any],
    coordinates: [CLLocationCoordinate2D],
    holes: [[CLLocationCoordinate2D]]
  ) {
    self.customId = customId
    self.json = json
    super.init()
    var coords = coordinates
    _ = super.setPolygonWithCoordinates(&coords, count: coords.count)
    // 孔洞：SDK 11.x 移除了 interiorPolygons 老属性，但 hollowShapes（since
    // 5.5.0）仍在 —— 官方 PolygonOverlayViewController 的标准挖孔用法。
    // 洞 overlay 仅挂在 hollowShapes，不添加到地图；renderer 自动渲染镂空。
    // SDK 约定：洞只支持 MAPolygon/MACircle，须在多边形内部、不与边相交、
    // 彼此不相交、不支持嵌套（与 Android GeoJSON/官方语义一致）。
    guard !holes.isEmpty else { return }
    let shapes: [MAOverlay] = holes.filter { $0.count >= 3 }.map { hole in
      var pts = hole
      let shape = MAPolygon()
      _ = shape.setPolygonWithCoordinates(&pts, count: pts.count)
      return shape
    }
    if !shapes.isEmpty {
      hollowShapes = shapes
    }
  }
}

final class QsCircle: MACircle {
  let customId: String
  let json: [String: Any]
  init(customId: String, json: [String: Any]) {
    self.customId = customId
    self.json = json
    super.init()
  }
}

/// 承载高德 [MAMapView] 的 PlatformView。
///
/// 每个实例持有独立通道 `amap_maps_flutter_qs/map#<viewId>`。
/// **通道名以引擎分配的 viewId 为键**（create 的 viewIdentifier，与 Dart
/// onPlatformViewCreated 收到的是同一个值），两端无需依赖 creationParams
/// 内容即可对齐通道名 —— creationParams 仅为业务数据（相机/覆盖物等），
/// 即使引擎未送达（部分 Flutter 版本 args=nil），通道依然可用，仅初始
/// 配置延迟到 Dart 经主通道 `map#attach` 补送。
///
/// 覆盖物同步：与 Android 端一致，Dart 侧差量 diff 后下发
/// `toAdd / toUpdate / toRemove`；update 一律「删旧 + 建新」。
///
/// 相机操作使用 iOS SDK 的 `MAMapStatus` + `setMapStatus:animated:duration:`
/// 体系（与官方 amap_flutter_map 一致）；iOS SDK 无 MACameraUpdate/MACameraPosition。
public class AMapPlatformView: NSObject, FlutterPlatformView {
  /// 当前存活地图实例的通道注册表（platform 线程写入，仅供诊断探针读取）。
  /// 通过主通道 `debug#listMaps` 可查询，用于定位 Dart/Native 通道名不一致问题。
  static private(set) var liveChannelNames: [String] = []

  /// 当前存活地图实例注册表（viewId → 实例），供主通道 `map#attach` 定位视图。
  static var viewsByViewId: [Int64: AMapPlatformView] = [:]

  /// 日志/诊断用的实例标识。与通道键一致，取引擎 viewId
  /// （Dart 侧插件内 mapId 计数器与 viewId 通常相同但无保证，attach 时会记录两者）。
  private let mapId: Int
  private let viewId: Int64
  private let messenger: FlutterBinaryMessenger
  private let mapView: MAMapView
  private let channel: FlutterMethodChannel
  private let channelName: String
  /// 初始配置（相机/覆盖物等）是否已应用。args=nil 时等 attach 补送。
  private var configured = false
  private var disposed = false

  /// 相机操作就绪条件：**frame 非空 + SDK mapInitComplete**，二者缺一不可。
  ///
  /// 实测（SDK 11.2 真机）：
  /// - 0×0 frame 下 setMapStatus：中心被算到 Mercator 极值角 (85.05N, -179.99W)；
  /// - frame 已就绪但 SDK 未 initComplete：同样算到极值角（zoom 能生效、中心不生效）。
  /// MAMapViewDelegate.mapInitComplete: 注释明确「地图初始化完成（在此之后，
  /// 可以进行坐标计算）」—— 这就是坐标类操作（setMapStatus 等）的最早安全时机。
  private var pendingCameraWork: [() -> Void] = []
  private var frameObservation: NSKeyValueObservation?
  private var isMapInitComplete = false

  /// 满足「frame 非空 + mapInitComplete」时按序冲刷挂起的相机操作。
  private func flushPendingCameraWorkIfNeeded() {
    guard isMapInitComplete, !mapView.frame.isEmpty, !pendingCameraWork.isEmpty else { return }
    frameObservation?.invalidate()
    frameObservation = nil
    let works = pendingCameraWork
    pendingCameraWork = []
    AMapLog.d(
      "map#\(mapId) 相机就绪（frame=\(mapView.frame) + mapInitComplete），"
        + "执行挂起相机操作 \(works.count) 项")
    works.forEach { $0() }
  }

  /// frame/SDK 未就绪时挂起相机操作，就绪后按序执行。
  private func runWhenCameraReady(_ work: @escaping () -> Void) {
    if isMapInitComplete, !mapView.frame.isEmpty {
      work()
      return
    }
    if frameObservation == nil {
      frameObservation = mapView.observe(\.frame, options: [.new]) { [weak self] _, _ in
        self?.flushPendingCameraWorkIfNeeded()
      }
    }
    pendingCameraWork.append(work)
    AMapLog.d(
      "map#\(mapId) 相机操作挂起（frame=\(mapView.frame.isEmpty ? "0×0" : "已就绪")"
        + " mapInitComplete=\(isMapInitComplete)）")
  }

  /// 气泡占位符：零宽空格。annotation 无 title 时点击选中不弹 callout（SDK
  /// 约定），content 模式用零宽空格兜底 —— 不可见，且不会被非空校验的
  /// trim 判为空。与 Android 端 INFO_WINDOW_PLACEHOLDER 同语义。
  private static let infoWindowPlaceholder = "\u{200B}"

  private var markersById: [String: QsMarker] = [:]
  private var polylinesById: [String: QsPolyline] = [:]
  private var polygonsById: [String: QsPolygon] = [:]
  private var circlesById: [String: QsCircle] = [:]

  /// rendererFor 委托是否被 SDK 调用过（覆盖物渲染管线活性探针）。
  private var overlayRendererRequested = false
  /// 是否已执行过覆盖物重加（每块地图一次）。
  private var didResyncOverlays = false
  // 程序化选中（InfoWindow.show / showInfoWindow）期间的 didSelect 抑制表
  private var programmaticSelection = Set<String>()
  // 待弹出气泡的 marker id：annotation view 尚未创建时（addAnnotation 后
  // viewFor 在下一次布局才调用），selectAnnotation 是 no-op，须等
  // didAddAnnotationViews 回来再真正选中
  private var pendingShowSelection = Set<String>()
  // viewFor 已实际创建过 view 的 marker id（showInfoWindow 就绪判断依据）
  private var markerViewsCreated = Set<String>()

  /// mapLoaded 是否已回发过（mapViewDidFinishLoadingMap 在底图每次重新
  /// 加载完成时都会回调——缩放/平移后瓦片重载也触发，真机实测一次会话
  /// 可回调多次；onMapLoaded 语义为一次性事件，只回发首帧就绪）。
  private var didNotifyMapLoaded = false
  /// 最近一次已确认的程序化目标相机（回弹守卫用）。
  private var lastGoodCamera:
    (target: CLLocationCoordinate2D, zoom: CGFloat, bearing: CGFloat, tilt: CGFloat)?
  /// 程序化相机「落定窗口」截止时刻：窗口内出现的世界角回弹视为 SDK bug
  /// 并自动重设；窗口外（用户手势等）不干预，避免与手势打架/无限循环。
  private var cameraSettleDeadline = Date.distantPast
  /// 回弹守卫已执行的纠正次数（设上限防与 SDK 反复拉锯）。
  private var snapbackFixCount = 0
  /// cameraMove 载荷去重（regionChanged 空转时连续回调载荷完全相同）。
  /// 直接比较分量数值（空转回调的数值逐位相同，精确等值即可），
  /// 避免手势期间每帧对整个字典做字符串插值的分配开销。
  /// 注意：存储属性不能放 delegate extension（第四次踩坑）。
  private var lastCameraMove:
    (lat: Double, lng: Double, zoom: Double, bearing: Double, tilt: Double)?
  // marker 拖拽落点采样：SDK 在 .ending 时已把视图摆回静止位（坐标+offset），
  // 事后无法从 view.center 还原松手瞬间的锚点位置，须在拖拽过程中逐帧采样。
  // （存储属性不能放 delegate extension，第三次踩坑记录）
  private var dragTrackLink: CADisplayLink?
  private weak var dragTrackView: MAAnnotationView?
  private var dragLastCenter: CGPoint?
  private var dragLastCenterOffset: CGPoint?

  init(
    frame: CGRect,
    viewIdentifier viewId: Int64,
    messenger: FlutterBinaryMessenger,
    creationParams: [String: Any]
  ) {
    self.viewId = viewId
    mapId = Int(viewId)
    self.messenger = messenger
    // MAMapView.init 未标注可空性（Swift 按隐式解包导入），SDK 失败时实际会
    // 返回 nil——直接赋给非可选属性会在后续桥接（如 KVO）处触发难以定位的
    // "Non-Optional values are not allowed to hold null pointers" SIGABRT。
    // 此处立即判 nil 并给出明确诊断（fail-fast）。
    let created = MAMapView(frame: frame)
    if created == nil {
      AMapLog.d(
        "map#\(viewId) MAMapView 初始化返回 nil！最常见原因："
          + "①隐私合规未通过（须在创建任何 MAMapView 前调用 updatePrivacyShow/"
          + "updatePrivacyAgree 且状态为 didShow/didContain/didAgree）；"
          + "②APIKey 未注入（iOS 未配置有效 Key 时部分 SDK 版本会创建失败）。"
          + "请检查 Xcode 控制台高德 SDK 的原始报错。")
      fatalError(
        """
        amap_maps_flutter_qs: MAMapView init returned nil (frame=\(frame)).
        最常见原因：隐私合规未完成，或 iOS APIKey 未注入（示例工程请以 \
        --dart-define=AMAP_IOS_KEY=<你的Key> 传入）。详见 Xcode 控制台高德 SDK 输出。
        """)
    }
    mapView = created

    // 通道在 create 时即按 viewId 绑定（viewId 引擎已分配，两端确定一致），
    // 此刻起原生 handler 就绪 —— 后续 Dart 的所有调用都不会再
    // MissingPluginException，即使 creationParams 尚未送达。
    let name = "\(AmapMapsFlutterQsPlugin.mainChannelName)/map#\(viewId)"
    channelName = name
    channel = FlutterMethodChannel(name: name, binaryMessenger: messenger)
    super.init()

    channel.setMethodCallHandler(handleMapMethod)
    AMapPlatformView.liveChannelNames.append(name)
    AMapPlatformView.viewsByViewId[viewId] = self

    if creationParams.isEmpty {
      AMapLog.d(
        "map#\(viewId) 通道已绑定 \(name)；creationParams 为空 →"
          + "等待 Dart 经主通道 map#attach 补送参数后应用初始配置")
    } else {
      configured = true
      applyInitialOptions(creationParams)
      AMapLog.d("map#\(viewId) 通道已绑定 \(name)，初始配置已应用（create 参数正常送达）")
    }
  }

  /// Dart 侧 attach 握手入口（主通道 `map#attach` 调用）。
  ///
  /// 职责：补送初始参数（若 create 时 args=nil）+ 回发 mapCreated
  /// （此时 Dart handler 必已就绪，不会丢）。
  /// 返回值：已应用参数 → viewId；create 时参数已正常送达 → -2；找不到视图 → -3。
  static func attach(viewId: Int64, creationParams: [String: Any]) -> Int {
    guard let view = viewsByViewId[viewId] else {
      AMapLog.d("attach viewId=\(viewId)：注册表中无此视图（可能已 dispose）")
      return -3
    }
    if view.configured {
      AMapLog.d("attach viewId=\(viewId)：初始配置已在 create 时应用，仅回发 mapCreated")
    } else {
      view.configured = true
      view.applyInitialOptions(creationParams)
      AMapLog.d("attach viewId=\(viewId)：初始配置已应用（经主通道补送）")
    }
    view.notifyDartMapCreated()
    return Int(viewId)
  }

  public func view() -> UIView {
    mapView
  }

  // ---- 初始配置（creationParams） ----

  private func applyInitialOptions(_ params: [String: Any]) {
    // 地图类型：Dart 侧 MapType.nativeCode 为 Android 编码 1..5，
    // iOS MAMapType 为 0..4（Standard=0/Satellite=1/Night=2/Navi=3/Bus=4，
    // 官方插件 Dart 传 mapType.index 后 iOS 直接赋值），故统一 -1 映射。
    if let typeCode = params["mapType"] as? Int {
      applyMapTypeCode(typeCode)
    }

    // 地图语言：0=中文 / 1=英文（英文仅标准地图生效，与自定义样式互斥）
    if let langCode = params["language"] as? Int {
      mapView.mapLanguage = NSNumber(value: langCode)
    }

    // 缩放范围：iOS SDK 为独立属性 minZoomLevel / maxZoomLevel
    if let minZoom = params["minZoom"] as? Double {
      mapView.minZoomLevel = CGFloat(minZoom)
    }
    if let maxZoom = params["maxZoom"] as? Double {
      mapView.maxZoomLevel = CGFloat(maxZoom)
    }

    // 定位蓝点：enabled 控制 showsUserLocation，样式经 MAUserLocationRepresentation
    mapView.showsUserLocation = (params["myLocationEnabled"] as? Bool) ?? false
    if let style = params["myLocationStyle"] as? [String: Any] {
      applyMyLocationStyle(style)
    }

    // 手势开关（US-04）
    applyGestures(params["gestures"])

    // UI 开关（路况/POI 点击/建筑物/标注/指南针/比例尺）
    applyUiOptions(params["uiOptions"])

    // 自定义地图样式（本地样式数据优先，其次云端样式 ID）
    if let style = params["customStyle"] as? [String: Any] {
      applyCustomStyle(style)
    }

    // 初始相机
    if let camera = params["initialCameraPosition"] as? [String: Any] {
      applyCameraPosition(camera)
    }

    // 可视范围限制（limitMapRect；官方在 frame 未布局完成时通过 KVO
    // 延迟设置，MVP 先直接设置，平台视图 frame 在 create 时已给出）
    if let bounds = params["limitBounds"] {
      applyLimitBounds(bounds)
    }

    // 覆盖物初始渲染
    let markerCount = (params["markers"] as? [[String: Any]])?.count ?? 0
    let polylineCount = (params["polylines"] as? [[String: Any]])?.count ?? 0
    let polygonCount = (params["polygons"] as? [[String: Any]])?.count ?? 0
    let circleCount = (params["circles"] as? [[String: Any]])?.count ?? 0
    AMapLog.d(
      "map#\(mapId) 初始覆盖物: markers=\(markerCount) polylines=\(polylineCount)"
        + " polygons=\(polygonCount) circles=\(circleCount)")
    (params["markers"] as? [[String: Any]])?.forEach(addMarker)
    (params["polylines"] as? [[String: Any]])?.forEach(addPolyline)
    (params["polygons"] as? [[String: Any]])?.forEach(addPolygon)
    (params["circles"] as? [[String: Any]])?.forEach(addCircle)

    bindMapEvents()
  }

  /// Dart MapType.nativeCode（Android 编码 1..5）→ iOS MAMapType（0..4）。
  private func applyMapTypeCode(_ code: Int) {
    let raw = code - 1
    mapView.mapType = MAMapType(rawValue: raw) ?? .standard
  }

  /// 手势开关（创建时与动态更新共用）。
  private func applyGestures(_ json: Any?) {
    guard let gestures = json as? [String: Bool] else { return }
    if let zoom = gestures["zoom"] { mapView.isZoomEnabled = zoom }
    if let scroll = gestures["scroll"] { mapView.isScrollEnabled = scroll }
    if let rotate = gestures["rotate"] { mapView.isRotateEnabled = rotate }
    // 倾斜手势：iOS SDK 对应属性为 rotateCameraEnabled（官方插件同款用法）
    if let tilt = gestures["tilt"] { mapView.isRotateCameraEnabled = tilt }
  }

  /// UI 开关类选项（属性名与官方 amap_flutter_map 的 MAMapView+Flutter 一致）。
  private func applyUiOptions(_ json: Any?) {
    guard let options = json as? [String: Any] else { return }
    if let traffic = options["trafficEnabled"] as? Bool {
      mapView.isShowTraffic = traffic
    }
    if let touchPoi = options["touchPoiEnabled"] as? Bool {
      mapView.touchPOIEnabled = touchPoi
    }
    if let buildings = options["buildingsEnabled"] as? Bool {
      mapView.isShowsBuildings = buildings
    }
    if let labels = options["labelsEnabled"] as? Bool {
      mapView.isShowsLabels = labels
    }
    if let compass = options["compassEnabled"] as? Bool {
      mapView.showsCompass = compass
    }
    if let scale = options["scaleEnabled"] as? Bool {
      mapView.showsScale = scale
    }
    // zoomControlsEnabled（Android 右下角 +/- 缩放按钮）为 Android 独有 UI，
    // MAMapView 无对应属性，此处有意不处理
  }

  /// 自定义地图样式（对齐 Android `applyCustomStyle`）。
  ///
  /// 优先级与 Android 一致：本地样式数据（styleData / styleExtraData）优先，
  /// 两者都为空时回落云端样式 ID（customStyleId，本插件扩展）。
  /// 注意：iOS SDK 7.0.0 起样式文件格式有更新，Dart 侧需使用官网新导出的样式数据；
  /// 启用自定义样式后 `mapContentApprovalNumber()` 将返回 nil（SDK 约定）。
  /// Dart Uint8List 经通道到达时为 FlutterStandardTypedData，此处统一解出 Data。
  private func applyCustomStyle(_ json: [String: Any]) {
    let enabled = (json["enabled"] as? Bool) ?? true
    guard enabled else { return }
    let options = MAMapCustomStyleOptions()
    let styleData = channelData(json["styleData"])
    let styleExtraData = channelData(json["styleExtraData"])
    if let data = styleData, !data.isEmpty {
      options.styleData = data
    }
    if let data = styleExtraData, !data.isEmpty {
      options.styleExtraData = data
    }
    if styleData == nil && styleExtraData == nil {
      if let styleId = json["customStyleId"] as? String, !styleId.isEmpty {
        options.styleId = styleId
      }
    }
    mapView.setCustomMapStyleOptions(options)
    mapView.customMapStyleEnabled = true
  }

  /// 通道二进制数据解码：Dart Uint8List → FlutterStandardTypedData → Data。
  private func channelData(_ json: Any?) -> Data? {
    if let typed = json as? FlutterStandardTypedData {
      return typed.data
    }
    return json as? Data
  }

  /// 定位蓝点样式（对齐 Android `applyMyLocationStyle`）。
  ///
  /// iOS SDK 与 Android 的样式能力不完全对等，映射约定：
  /// - `locationMode`：show/locate → 不跟踪（None，蓝点仅随定位刷新）；
  ///   follow → Follow（蓝点保持地图中心）；mapRotate（地图随行进方向旋转）
  ///   iOS 无对应能力，近似为 FollowWithHeading（罗盘朝向）；
  ///   locationRotate → FollowWithHeading。
  /// - `icon` → 蓝点图标；`circleFillColor`/`circleStrokeColor`（ARGB int）
  ///   → 精度圈填充/描边；`circleStrokeWidth`（dp）→ 圈线宽。
  /// 注意：不在 iOS 端强制 showsUserLocation —— 与 Android 一致，显示与否
  /// 由 `myLocationEnabled` 单独控制。
  private func applyMyLocationStyle(_ json: [String: Any]) {
    let representation = MAUserLocationRepresentation()
    representation.showsAccuracyRing = true
    if let image = qsImage(from: json["icon"], screenScale: screenScale) {
      representation.image = image
    } else if let icon = json["icon"] {
      AMapLog.d("map#\(mapId) myLocationStyle 图标解码为 nil，用 SDK 默认蓝点 icon=\(icon)")
    }
    if json["circleFillColor"] != nil {
      representation.fillColor = color(
        json["circleFillColor"],
        fallback: UIColor(red: 136 / 255.0, green: 166 / 255.0, blue: 227 / 255.0, alpha: 0.3))
    }
    if json["circleStrokeColor"] != nil {
      representation.strokeColor = color(
        json["circleStrokeColor"], fallback: UIColor.blue.withAlphaComponent(0.6))
    }
    if let width = json["circleStrokeWidth"] as? Double {
      representation.lineWidth = CGFloat(width)
    }
    // ObjC updateUserLocationRepresentation: 在 Swift 中导入为 update(_:)（11.x 重命名）
    mapView.update(representation)

    switch json["locationMode"] as? String {
    case "follow":
      mapView.userTrackingMode = .follow
    case "mapRotate", "locationRotate":
      mapView.userTrackingMode = .followWithHeading
    default:
      // show / locate：仅显示蓝点，不持续跟踪（iOS 无"首次定位移动到中心"等价 API）
      mapView.userTrackingMode = .none
    }
  }

  /// 经纬度 bounds JSON（[[lat,lng],[lat,lng]]）→ MAMapRect。
  ///
  /// MAMapPointForCoordinate 输出与缩放无关的世界地图投影点，
  /// 取两角投影点的包围矩形即为该 bounds 的 map rect。
  private func mapRect(fromBoundsJson json: Any?) -> MAMapRect? {
    guard let list = json as? [Any], list.count >= 2,
      let sw = jsonToLatLng(list[0]), let ne = jsonToLatLng(list[1])
    else { return nil }
    let pSW = MAMapPointForCoordinate(sw)
    let pNE = MAMapPointForCoordinate(ne)
    let originX = min(pSW.x, pNE.x)
    let originY = min(pSW.y, pNE.y)
    let width = abs(pSW.x - pNE.x)
    let height = abs(pSW.y - pNE.y)
    return MAMapRectMake(originX, originY, width, height)
  }

  private func applyLimitBounds(_ json: Any?) {
    if let rect = mapRect(fromBoundsJson: json), rect.size.width > 0, rect.size.height > 0 {
      mapView.limitMapRect = rect
      limitBoundsActive = true
    } else {
      // 解除限制。**严禁设零矩形**（2026-11-03 定案的蓝屏真根因）：
      // limitMapRect 语义是「可见区域的矩形边界」，零矩形=把可见区域钳制到
      // 世界原点（85.05N/-180W）的退化矩形，SDK 随后强制调整 zoom 适配
      // （实测 zoom 12→11.88→10.9 持续衰减）→ 可见区域停在世界角落 → 蓝屏。
      // 之前误诊为 SDK 11.x 的 iOS 26 bug 并设 limitMapRect workaround，
      // 实为「设了非零 limit 掩盖了零矩形 limit 的自伤」。
      // 处理：从未设过 limit 时不碰属性；解除时用全世界矩形恢复无限制。
      guard limitBoundsActive else { return }
      mapView.limitMapRect = MAMapRectMake(0, 0, MAMapSizeWorld.width, MAMapSizeWorld.height)
      limitBoundsActive = false
      AMapLog.d("map#\(mapId) limitBounds 已解除（恢复全世界范围）")
    }
  }

  /// 业务 limitBounds 是否处于生效状态（用于解除时判断，避免误设零矩形）。
  private var limitBoundsActive = false

  private func applyCameraPosition(_ json: [String: Any]) {
    guard let target = jsonToLatLng(json["target"]) else { return }
    let zoom = CGFloat((json["zoom"] as? Double) ?? 10)
    let bearing = CGFloat((json["bearing"] as? Double) ?? 0)
    let tilt = CGFloat((json["tilt"] as? Double) ?? 0)
    lastInitialCamera = (target: target, zoom: zoom, bearing: bearing, tilt: tilt)
    runWhenCameraReady { [weak self] in
      self?.applyInitialCameraNow(
        target: target, zoom: zoom, bearing: bearing, tilt: tilt)
    }
  }

  /// 记录最近一次初始相机（mapLoaded 后二次校正用）。
  private var lastInitialCamera:
    (target: CLLocationCoordinate2D, zoom: CGFloat, bearing: CGFloat, tilt: CGFloat)?

  /// 立即应用相机（须在 frame 非空 + mapInitComplete 之后调用）。
  ///
  /// 实测（SDK 11.2 真机）：mapInitComplete 时 setMapStatus 会更新逻辑状态
  /// （centerCoordinate/cameraMoveEnd 正确），但渲染管线可能仍停在世界原点角
  /// （点击换算、瓦片均在极值角）。因此应用后用 visibleMapRect 校验，
  /// 未真正生效则用基础 API（setZoomLevel + setCenterCoordinate）兜底。
  private func applyInitialCameraNow(
    target: CLLocationCoordinate2D, zoom: CGFloat, bearing: CGFloat, tilt: CGFloat
  ) {
    // 全新构造 MAMapStatus（对齐官方 amap_map setCameraPosition）：
    // 不复用 getMapStatus() 返回的状态，避免脏字段影响。
    let status = MAMapStatus(
      center: target,
      zoomLevel: zoom,
      rotationDegree: bearing,
      cameraDegree: tilt,
      screenAnchor: mapView.screenAnchor)
    mapView.setMapStatus(status, animated: false, duration: 0)
    if !isRenderedCameraNear(target) {
      mapView.setZoomLevel(zoom, animated: false)
      mapView.setCenter(target, animated: false)
    }
    lastGoodCamera = (target: target, zoom: zoom, bearing: bearing, tilt: tilt)
    cameraSettleDeadline = Date().addingTimeInterval(3)
  }

  /// 渲染可见区域中心是否已接近目标点（± 一个视口宽度内视为已生效）。
  private func isRenderedCameraNear(_ target: CLLocationCoordinate2D) -> Bool {
    let rect = mapView.visibleMapRect
    let width = Double(rect.size.width)
    guard width > 0 else { return false }
    let p = MAMapPointForCoordinate(target)
    let midX = Double(rect.origin.x) + width / 2
    let midY = Double(rect.origin.y) + Double(rect.size.height) / 2
    let dx = midX - Double(p.x)
    let dy = midY - Double(p.y)
    return (dx * dx + dy * dy).squareRoot() <= width
  }

  /// Double 兜底转换：CGFloat 装箱后 as? Double 为 nil，需显式转。
  private func dbl(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let c = v as? CGFloat { return Double(c) }
    return nil
  }

  /// 屏幕像素比（替代已弃用的 UIScreen.main.scale）。
  /// 优先读地图视图自身 traitCollection（挂到 window 后可靠），未挂载时
  /// 尝试 window 所在 screen 与 UITraitCollection.current；全部无效时按 1
  /// 处理（仅极端时序可达，最坏结果是图标按 1x 解释略糊，不会出错）。
  private var screenScale: CGFloat {
    let t = mapView.traitCollection.displayScale
    if t > 0 { return t }
    if let s = mapView.window?.screen.scale, s > 0 { return s }
    let current = UITraitCollection.current.displayScale
    return current > 0 ? current : 1
  }

  /// 世界角回弹检测：zoom≥6 时纬度≥80 或 |经度|≥179 属于不可能的正常状态
  /// （zoom 6 视口约 6°，从国内正常视角无法合法到达极区角）。
  private func isImplausibleCameraTarget(lat: Double, lng: Double, zoom: Double) -> Bool {
    zoom >= 6 && (lat >= 80 || abs(lng) >= 179)
  }

  /// 落定窗口内的世界角回弹守卫。
  ///
  /// 真机日志（2026-11-03，iOS 26.6.2 / SDK 11.3.100）：setMapStatus 后瞬时
  /// centerCoordinate 与 visibleMapRect 均正确（中心/探针=1.0000），但下一次
  /// 布局把可见区域弹回世界西北角（cameraMoveEnd 上报 85N/-180），且
  /// regionChanged 高频空转。此处检测回弹并重设相机（上限 5 次防拉锯）。
  private func fixSnapbackIfWorldCorner(_ json: [String: Any]) {
    guard Date() < cameraSettleDeadline, snapbackFixCount < 5,
      let t = json["target"] as? [Double], t.count == 2,
      isImplausibleCameraTarget(lat: t[0], lng: t[1], zoom: dbl(json["zoom"]) ?? 0),
      let cam = lastGoodCamera
    else { return }
    snapbackFixCount += 1
    AMapLog.d("map#\(mapId) 检测到世界角回弹（target=\(t)），重设相机 #\(snapbackFixCount)")
    applyInitialCameraNow(target: cam.target, zoom: cam.zoom, bearing: cam.bearing, tilt: cam.tilt)
  }

  /// 取当前地图状态；getMapStatus 正常情况下非空，兜底用官方指定初始化器构造。
  private func currentMapStatus() -> MAMapStatus {
    mapView.getMapStatus()
      ?? MAMapStatus(
        center: CLLocationCoordinate2D(latitude: 39.909187, longitude: 116.397451),
        zoomLevel: 10, rotationDegree: 0, cameraDegree: 0,
        screenAnchor: CGPoint(x: 0.5, y: 0.5))
  }

  private func bindMapEvents() {
    mapView.delegate = self
  }

  // ---- 覆盖物构建 ----

  private func addMarker(_ json: [String: Any]) {
    guard let id = json["id"] as? String else {
      AMapLog.d("map#\(mapId) addMarker 丢弃：缺少 id，json=\(json.keys.sorted())")
      return
    }
    guard markersById[id] == nil else {
      AMapLog.d("map#\(mapId) addMarker 丢弃：id=\(id) 已存在")
      return
    }
    guard let position = jsonToLatLng(json["position"]) else {
      AMapLog.d("map#\(mapId) addMarker 丢弃：id=\(id) position 解析失败（需要 [lat,lng]）")
      return
    }
    let marker = QsMarker(customId: id, json: json)
    marker.coordinate = position
    var showOnCreate = false
    if let info = json["infoWindow"] as? [String: Any] {
      marker.title = info["title"] as? String
      marker.subtitle = info["snippet"] as? String
      // content 模式（Widget 截图气泡）：title/subtitle 兜底非空 ——
      // annotation 无 title 时点击选中不弹 callout（与 Android SDK 约定一致）。
      // 用零宽空格占位：不可见，且不会被非空校验的 trim 判为空
      if qsImage(from: info["content"], screenScale: screenScale) != nil {
        if marker.title == nil { marker.title = Self.infoWindowPlaceholder }
        if marker.subtitle == nil { marker.subtitle = Self.infoWindowPlaceholder }
      }
      showOnCreate = (info["show"] as? Bool) == true
    }
    markersById[id] = marker
    // 显式 addAnnotation：MAMapView.add(_:) 会把参数送进 overlay 渲染管线
    // （rendererFor 收到 QsMarker → 不渲染，Marker 从不显示），必须走
    // annotation 通道（viewFor: → MAAnnotationView 大头针）。
    mapView.addAnnotation(marker)
    AMapLog.d("map#\(mapId) addMarker 成功 id=\(id) position=\(position)")
    // 默认显示气泡（InfoWindow.show）：不能在这里同步 selectAnnotation ——
    // annotation view 尚未创建（viewFor 在下一次布局才被调用），select 是
    // no-op。挂入 pending 集合，didAddAnnotationViews 里真正选中。
    if showOnCreate {
      pendingShowSelection.insert(id)
    }
  }

  private func addPolyline(_ json: [String: Any]) {
    let points = jsonToLatLngList(json["points"])
    guard let id = json["id"] as? String else {
      AMapLog.d("map#\(mapId) addPolyline 丢弃：缺少 id")
      return
    }
    guard polylinesById[id] == nil else {
      AMapLog.d("map#\(mapId) addPolyline 丢弃：id=\(id) 已存在")
      return
    }
    guard points.count >= 2 else {
      AMapLog.d("map#\(mapId) addPolyline 丢弃：id=\(id) 点数不足（\(points.count) < 2）")
      return
    }
    let polyline = QsPolyline(customId: id, json: json)
    var pts = points
    let setOk = polyline.setPolylineWithCoordinates(&pts, count: pts.count)
    polylinesById[id] = polyline
    // 注意：addOverlay: 在 Swift 中被改名为 add(_:)（仅此重载接受 MAOverlay）；
    // MAPointAnnotation 经 MABaseOverlay 隐式 conforms MAOverlay，marker 若也用
    // add(_:) 会被误送 overlay 管线 —— marker 必须显式走 addAnnotation(_:)。
    mapView.add(polyline)
    AMapLog.d(
      "map#\(mapId) addPolyline 成功 id=\(id) 点数=\(points.count)"
        + " setPolyline=\(setOk) texture=\(json["customTexture"] != nil ? "有" : "无")"
        + " cap=\(json["capType"] ?? "-") dash=\(json["dashLineType"] ?? "-")")
  }

  private func addPolygon(_ json: [String: Any]) {
    let points = jsonToLatLngList(json["points"])
    guard let id = json["id"] as? String else {
      AMapLog.d("map#\(mapId) addPolygon 丢弃：缺少 id")
      return
    }
    guard polygonsById[id] == nil else {
      AMapLog.d("map#\(mapId) addPolygon 丢弃：id=\(id) 已存在")
      return
    }
    guard points.count >= 3 else {
      AMapLog.d("map#\(mapId) addPolygon 丢弃：id=\(id) 点数不足（\(points.count) < 3）")
      return
    }
    let holes = (json["holes"] as? [[Any]])?.compactMap(jsonToLatLngList) ?? []
    let polygon = QsPolygon(
      customId: id, json: json, coordinates: points, holes: holes)
    polygonsById[id] = polygon
    mapView.add(polygon)
    AMapLog.d("map#\(mapId) addPolygon 成功 id=\(id) 点数=\(points.count)")
  }

  private func addCircle(_ json: [String: Any]) {
    guard let id = json["id"] as? String else {
      AMapLog.d("map#\(mapId) addCircle 丢弃：缺少 id")
      return
    }
    guard circlesById[id] == nil else {
      AMapLog.d("map#\(mapId) addCircle 丢弃：id=\(id) 已存在")
      return
    }
    guard let center = jsonToLatLng(json["center"]) else {
      AMapLog.d("map#\(mapId) addCircle 丢弃：id=\(id) center 解析失败（需要 [lat,lng]）")
      return
    }
    let radius = (json["radius"] as? Double) ?? 0
    let circle = QsCircle(customId: id, json: json)
    circle.coordinate = center
    circle.radius = radius
    circlesById[id] = circle
    mapView.add(circle)
    AMapLog.d("map#\(mapId) addCircle 成功 id=\(id) radius=\(radius)")
  }

  private func removeMarker(_ id: String) {
    pendingShowSelection.remove(id)
    // 程序化选中若因 marker 先被删除而未被 didSelect 消费，id 会永久残留，
    // 之后重建同 id marker 时用户的真实点击会被抑制逻辑吞掉一次
    programmaticSelection.remove(id)
    markerViewsCreated.remove(id)
    if let marker = markersById.removeValue(forKey: id) {
      mapView.removeAnnotation(marker)
    }
  }

  private func removePolyline(_ id: String) {
    if let polyline = polylinesById.removeValue(forKey: id) {
      mapView.remove(polyline)
    }
  }

  private func removePolygon(_ id: String) {
    if let polygon = polygonsById.removeValue(forKey: id) {
      mapView.remove(polygon)
    }
  }

  private func removeCircle(_ id: String) {
    if let circle = circlesById.removeValue(forKey: id) {
      mapView.remove(circle)
    }
  }

  private func applyOverlayUpdates(
    _ payload: Any?,
    add: ([String: Any]) -> Void,
    remove: (String) -> Void
  ) {
    guard let map = payload as? [String: Any] else {
      AMapLog.d("map#\(mapId) overlay 更新载荷解析失败: \(type(of: payload))")
      return
    }
    let toRemove = (map["toRemove"] as? [String])?.count ?? 0
    let toAdd = (map["toAdd"] as? [[String: Any]])?.count ?? 0
    let toUpdate = (map["toUpdate"] as? [[String: Any]])?.count ?? 0
    AMapLog.d("map#\(mapId) overlay 更新: add=\(toAdd) update=\(toUpdate) remove=\(toRemove)")
    (map["toRemove"] as? [String])?.forEach(remove)
    (map["toAdd"] as? [[String: Any]])?.forEach(add)
    (map["toUpdate"] as? [[String: Any]])?.forEach { json in
      guard let id = json["id"] as? String else { return }
      remove(id)
      add(json)
    }
  }

  // ---- MethodChannel ----

  private func handleMapMethod(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "map#moveCamera":
      // payload: {update, animated, durationMs}
      let args = call.arguments as? [String: Any]
      guard let update = args?["update"] else {
        result(FlutterError(code: "BAD_ARGS", message: "invalid camera update", details: nil))
        return
      }
      let animated = (args?["animated"] as? Bool) ?? false
      // durationMs（Dart 传 int，毫秒）→ setMapStatus 的 duration（秒）
      let durationMs =
        (args?["durationMs"] as? Double)
        ?? ((args?["durationMs"] as? Int).map { Double($0) })
        ?? 250
      applyCameraUpdate(update, animated: animated, duration: durationMs / 1000.0)
      result(nil)

    case "map#animateCamera":
      let args = (call.arguments as? [String: Any]) ?? [:]
      guard let update = args["update"] else {
        result(FlutterError(code: "BAD_ARGS", message: "invalid camera update", details: nil))
        return
      }
      let durationMs =
        (args["durationMs"] as? Double)
        ?? ((args["durationMs"] as? Int).map { Double($0) })
        ?? 250
      applyCameraUpdate(update, animated: true, duration: durationMs / 1000.0)
      result(nil)

    case "map#getCameraPosition":
      result(cameraJson())

    case "map#getVisibleRegion":
      // map point 坐标系 y 轴向下：南 = origin.y + height，东 = origin.x + width
      let rect = mapView.visibleMapRect
      let sw = MACoordinateForMapPoint(
        MAMapPointMake(rect.origin.x, rect.origin.y + rect.size.height))
      let ne = MACoordinateForMapPoint(
        MAMapPointMake(rect.origin.x + rect.size.width, rect.origin.y))
      result([sw.toJsonList(), ne.toJsonList()])

    case "map#getContentApprovalNumber":
      result(mapView.mapContentApprovalNumber())

    case "map#getSatelliteApprovalNumber":
      result(mapView.satelliteImageApprovalNumber())

    case "map#setMapType":
      if let typeCode = call.arguments as? Int {
        applyMapTypeCode(typeCode)
      }
      result(nil)

    case "map#setLanguage":
      if let langCode = call.arguments as? Int {
        mapView.mapLanguage = NSNumber(value: langCode)
        if langCode == 1 {
          AMapLog.d(
            "map#\(mapId) 地图语言 → 英文（注意：仅标准地图类型生效，与自定义样式互斥）")
        }
      }
      result(nil)

    case "map#dispose":
      // Dart State.dispose 驱动的资源释放（iOS 引擎无 platform view dispose
      // 生命周期，见 teardown 注释）
      teardown(reason: "dart-dispose")
      result(nil)

    case "map#setMinMaxZoomPreference":
      let json = call.arguments as? [String: Any] ?? [:]
      if let min = json["min"] as? Double {
        mapView.minZoomLevel = CGFloat(min)
      }
      if let max = json["max"] as? Double {
        mapView.maxZoomLevel = CGFloat(max)
      }
      result(nil)

    case "map#setLimitBounds":
      applyLimitBounds(call.arguments)
      result(nil)

    case "map#setUiOptions":
      applyUiOptions(call.arguments)
      result(nil)

    case "map#setGestures":
      applyGestures(call.arguments)
      result(nil)

    case "map#updateMarkers":
      applyOverlayUpdates(call.arguments, add: addMarker, remove: removeMarker)
      result(nil)

    case "map#updatePolylines":
      applyOverlayUpdates(call.arguments, add: addPolyline, remove: removePolyline)
      result(nil)

    case "map#updatePolygons":
      applyOverlayUpdates(call.arguments, add: addPolygon, remove: removePolygon)
      result(nil)

    case "map#updateCircles":
      applyOverlayUpdates(call.arguments, add: addCircle, remove: removeCircle)
      result(nil)

    case "map#showInfoWindow":
      if let id = call.arguments as? String, let marker = markersById[id] {
        if markerViewsCreated.contains(id) {
          // view 已创建：立即选中；didSelect 抑制避免程序化弹气泡误报用户点击
          programmaticSelection.insert(id)
          mapView.selectAnnotation(marker, animated: false)
          AMapLog.d("map#\(mapId) showInfoWindow id=\(id)（view 已就绪）")
        } else {
          // view 未创建（刚重建/离屏）：挂起，didAddAnnotationViews 补选
          pendingShowSelection.insert(id)
          AMapLog.d("map#\(mapId) showInfoWindow id=\(id)（view 未创建，挂起待补选）")
        }
      } else {
        AMapLog.d("map#\(mapId) showInfoWindow 丢弃：marker 不存在")
      }
      result(nil)

    case "map#hideInfoWindow":
      if let id = call.arguments as? String, let marker = markersById[id] {
        pendingShowSelection.remove(id)
        // 同 removeMarker：didSelect 未触达时残留条目会吞掉下一次真实点击
        programmaticSelection.remove(id)
        mapView.deselectAnnotation(marker, animated: false)
      }
      result(nil)

    case "map#takeSnapshot":
      // 对齐 Android getMapScreenShot：异步截取当前视口（含 annotationView），
      // 返回 PNG bytes。SDK 6.0+ 推荐 takeSnapshotInRect:withCompletionBlock:，
      // state：0=底图载入不完整、1=完整（与 Android 一样不因不完整而失败，仅记日志）。
      // 注意官方注释：不要在地图回调方法内直接调用 —— method channel 调用无此限制。
      mapView.takeSnapshot(in: mapView.bounds, withCompletionBlock: { [weak self] image, state in
        // result 必须恰好应答一次：self 释放（地图已 dispose）时也要应答，
        // 否则 Dart 侧 Future 永久悬挂。self 仅用于日志。
        guard let png = image?.pngData() else {
          AMapLog.d("map#\(self?.mapId ?? -1) takeSnapshot 失败：image 为空 state=\(state)")
          result(nil)
          return
        }
        AMapLog.d("map#\(self?.mapId ?? -1) takeSnapshot state=\(state) bytes=\(png.count)")
        result(png)
      })

    case "map#setCustomStyle":
      // 动态切换自定义样式（无需重建地图）；
      // null 或 enabled=false 关闭自定义样式
      if let style = call.arguments as? [String: Any],
        (style["enabled"] as? Bool) ?? true {
        applyCustomStyle(style)
      } else {
        mapView.customMapStyleEnabled = false
        AMapLog.d("map#\(mapId) 自定义样式已关闭")
      }
      result(nil)

    default:
      AMapLog.d("map#\(mapId) 未实现的原生方法: \(call.method)（Dart 侧调用了 iOS 端不支持的功能）")
      result(FlutterMethodNotImplemented)
    }
  }

  /// 应用相机更新（iOS SDK 无 MACameraUpdate，统一走 MAMapStatus；
  /// bounds 适配走 setVisibleMapRect:edgePadding:animated:，与官方一致）。
  private func applyCameraUpdate(_ payload: Any?, animated: Bool, duration: CFTimeInterval) {
    guard let json = payload as? [String: Any] else {
      AMapLog.d("map#\(mapId) camera update 载荷解析失败: \(type(of: payload))")
      return
    }
    let op = (json["op"] as? String) ?? "unknown"
    AMapLog.d("map#\(mapId) cameraUpdate op=\(op) animated=\(animated) duration=\(duration)s")
    runWhenCameraReady { [weak self] in
      self?.performCameraUpdate(json, animated: animated, duration: duration)
    }
  }

  private func performCameraUpdate(
    _ json: [String: Any], animated: Bool, duration: CFTimeInterval
  ) {
    switch json["op"] as? String {
    case "newLatLng":
      guard let target = jsonToLatLng(json["latLng"]) else {
        AMapLog.d("map#\(mapId) cameraUpdate newLatLng 解析失败: \(json["latLng"] ?? "nil")")
        return
      }
      let status = currentMapStatus()
      status.centerCoordinate = target
      mapView.setMapStatus(status, animated: animated, duration: duration)
    case "newLatLngZoom":
      guard let target = jsonToLatLng(json["latLng"]), let zoom = json["zoom"] as? Double
      else { return }
      let status = currentMapStatus()
      status.centerCoordinate = target
      status.zoomLevel = CGFloat(zoom)
      mapView.setMapStatus(status, animated: animated, duration: duration)
    case "newCameraPosition":
      guard let pos = json["cameraPosition"] as? [String: Any],
        let target = jsonToLatLng(pos["target"])
      else { return }
      let status = currentMapStatus()
      status.centerCoordinate = target
      status.zoomLevel = CGFloat((pos["zoom"] as? Double) ?? 10)
      status.cameraDegree = CGFloat((pos["tilt"] as? Double) ?? 0)
      status.rotationDegree = CGFloat((pos["bearing"] as? Double) ?? 0)
      mapView.setMapStatus(status, animated: animated, duration: duration)
    case "newLatLngBounds":
      // 退化矩形守卫（零尺寸 rect 会触发 SDK 异常 zoom 适配，与
      // limitMapRect 零矩形蓝屏同源的「退化矩形」陷阱）
      guard let rect = mapRect(fromBoundsJson: json["bounds"]),
        rect.size.width > 0, rect.size.height > 0
      else {
        AMapLog.d("map#\(mapId) cameraUpdate newLatLngBounds 矩形无效（缺失或零尺寸），跳过")
        return
      }
      let padding = (json["padding"] as? Double) ?? 0
      let inset = UIEdgeInsets(top: padding, left: padding, bottom: padding, right: padding)
      mapView.setVisibleMapRect(rect, edgePadding: inset, animated: animated)
    case "zoomTo":
      guard let zoom = json["zoom"] as? Double else { return }
      let status = currentMapStatus()
      status.zoomLevel = CGFloat(zoom)
      mapView.setMapStatus(status, animated: animated, duration: duration)
    case "zoomIn", "zoomOut", "zoomBy":
      // iOS SDK 无 zoomBy(delta) 等价 API，按 zoomLevel ± delta 近似
      // （官方插件对 zoomIn/zoomOut 同样是 zoomLevel ± 1）。
      let delta: Double
      switch json["op"] as? String {
      case "zoomIn": delta = 1
      case "zoomOut": delta = -1
      default: delta = (json["amount"] as? Double) ?? 0
      }
      let status = currentMapStatus()
      status.zoomLevel = status.zoomLevel + CGFloat(delta)
      mapView.setMapStatus(status, animated: animated, duration: duration)
    case "zoomByFocus":
      // 与 Android 端同款「焦点不动」换算（此前 iOS 降级为普通 zoomBy，
      // 两端行为分叉）。focus 为 Flutter 逻辑像素 = iOS point，无需换算。
      // 先按 min/max 钳制目标 zoom，再用有效缩放量反算缩放后应成为屏幕
      // 中心的地理点（不动点约束：缩放前后焦点屏幕位置不变）。
      let delta = (json["amount"] as? Double) ?? 0
      let bounds = mapView.bounds
      let focus = json["focus"] as? [Any]
      guard bounds.width > 0, bounds.height > 0,
        let focusList = focus, focusList.count >= 2,
        let fx = dbl(focusList[0]), let fy = dbl(focusList[1])
      else {
        // 焦点/视口无效：退化为普通缩放（保持旧兜底行为）
        let status = currentMapStatus()
        status.zoomLevel = status.zoomLevel + CGFloat(delta)
        mapView.setMapStatus(status, animated: animated, duration: duration)
        return
      }
      let newZoom = min(
        max(Double(mapView.zoomLevel) + delta, Double(mapView.minZoomLevel)),
        Double(mapView.maxZoomLevel))
      let effective = newZoom - Double(mapView.zoomLevel)
      let factor = pow(2.0, -effective)
      let w = Double(bounds.width)
      let h = Double(bounds.height)
      let anchorScreen = CGPoint(
        x: fx + (w / 2 - fx) * factor,
        y: fy + (h / 2 - fy) * factor)
      let status = currentMapStatus()
      status.centerCoordinate = mapView.convert(anchorScreen, toCoordinateFrom: mapView)
      status.zoomLevel = CGFloat(newZoom)
      mapView.setMapStatus(status, animated: animated, duration: duration)
    case "scrollBy":
      // Flutter 逻辑像素与 iOS point 一一对应，直接平移，不除 scale
      // （旧实现除以 scale 导致 3x 设备实际滚动距离只有请求量的 1/3）。
      // Android 端按官方惯例乘 density 转 px（google_maps_flutter 同款约定）。
      // 在地图自身坐标空间内平移中心点：旧实现用 mapView.center（superview
      // 坐标系）近似自身中心，改用 bounds 中点更严谨。
      let dx = (json["dx"] as? Double) ?? 0
      let dy = (json["dy"] as? Double) ?? 0
      let centerPoint = CGPoint(
        x: mapView.bounds.midX + CGFloat(dx),
        y: mapView.bounds.midY + CGFloat(dy))
      let status = currentMapStatus()
      status.centerCoordinate = mapView.convert(centerPoint, toCoordinateFrom: mapView)
      mapView.setMapStatus(status, animated: animated, duration: duration)
    default:
      break
    }
  }

  /// 当前相机位置 JSON（键与 Dart CameraPosition.fromJson 约定一致）。
  /// 注意：zoomLevel/cameraDegree/rotationDegree 是 CGFloat，Any 动态转
  /// `as? Double` 会返回 nil（实测 CGFloat as? Double == nil），必须显式转。
  private func cameraJson() -> [String: Any] {
    [
      "target": [
        mapView.centerCoordinate.latitude,
        mapView.centerCoordinate.longitude,
      ],
      "zoom": Double(mapView.zoomLevel),
      "tilt": Double(mapView.cameraDegree),
      "bearing": Double(mapView.rotationDegree),
    ]
  }

  // ---- 生命周期 ----

  /// 释放地图资源（幂等）。
  ///
  /// **iOS 引擎没有 platform view 的 dispose 生命周期**：FlutterPlatformView
  /// 协议头文件只有 `view` 一个方法（对比 Android 的 PlatformView.dispose），
  /// 因此引擎不会自动调用本类任何释放入口——本方法由 Dart 侧
  /// `AMapWidget` State.dispose 经 per-map 通道 `map#dispose` 驱动。
  ///
  /// MAMapView 是有限资源：同一进程同时存活约 10 个，超限后 SDK 拒绝创建
  /// 新地图（日志「地图同时创建已达上限」）。若不释放，连续开关地图页即耗尽配额。
  func teardown(reason: String) {
    guard !disposed else { return }
    disposed = true
    AMapLog.d(
      "map#\(mapId) 释放地图资源（reason=\(reason)，剩余活跃地图 "
        + "\(max(AMapPlatformView.liveChannelNames.count - 1, 0))）")
    frameObservation?.invalidate()
    frameObservation = nil
    stopDragTracking()
    dragTrackView = nil
    pendingCameraWork = []
    AMapPlatformView.viewsByViewId.removeValue(forKey: viewId)
    AMapPlatformView.liveChannelNames.removeAll { $0 == channelName }
    channel.setMethodCallHandler(nil)
    mapView.delegate = nil
    markersById.removeAll()
    programmaticSelection.removeAll()
    pendingShowSelection.removeAll()
    markerViewsCreated.removeAll()
    polylinesById.removeAll()
    polygonsById.removeAll()
    circlesById.removeAll()
    // 从视图层级摘除，打断引擎对 UIView 的持有链，让 MAMapView 能真正
    // dealloc（SDK 内部按实例存活数计数，dealloc 后配额即归还）
    mapView.removeFromSuperview()
  }

  /// 兼容入口：当前 Flutter 引擎不会调用（iOS FlutterPlatformView 协议无
  /// dispose 生命周期），保留以防未来引擎版本自动接入。
  public func dispose() {
    teardown(reason: "engine-dispose")
  }

  // ---- Dart 通知 ----

  private func notifyDartMapCreated() {
    notifyDart("mapCreated", mapId)
  }

  private func notifyDart(_ method: String, _ arguments: Any?) {
    channel.invokeMethod(method, arguments: arguments)
  }

  // ---- JSON 辅助 ----

  private func jsonToLatLng(_ json: Any?) -> CLLocationCoordinate2D? {
    guard let list = json as? [Any], list.count >= 2,
      let lat = list[0] as? Double, let lng = list[1] as? Double
    else { return nil }
    return CLLocationCoordinate2D(latitude: lat, longitude: lng)
  }

  private func jsonToLatLngList(_ json: Any?) -> [CLLocationCoordinate2D] {
    guard let list = json as? [Any] else { return [] }
    return list.compactMap(jsonToLatLng)
  }

  private func color(_ json: Any?, fallback: UIColor) -> UIColor {
    guard let argb = json as? Int else { return fallback }
    return UIColor(
      red: CGFloat((argb >> 16) & 0xFF) / 255,
      green: CGFloat((argb >> 8) & 0xFF) / 255,
      blue: CGFloat(argb & 0xFF) / 255,
      alpha: CGFloat((argb >> 24) & 0xFF) / 255)
  }
}

// MARK: - MAMapViewDelegate（事件回传 + 覆盖物视图/渲染器构建）

extension AMapPlatformView: MAMapViewDelegate {
  /// SDK 内部初始化完成（官方注释：此后方可进行坐标计算）。
  /// 这是 setMapStatus/坐标换算类操作的最早安全时机，冲刷挂起的相机操作。
  public func mapInitComplete(_ mapView: MAMapView) {
    AMapLog.d("map#\(mapId) mapInitComplete（SDK 坐标计算就绪）")
    isMapInitComplete = true
    flushPendingCameraWorkIfNeeded()
  }

  public func mapView(_ mapView: MAMapView, regionDidChangeAnimated animated: Bool) {
    let json = cameraJson()
    AMapLog.d("map#\(mapId) cameraMoveEnd \(json)")
    // 落定窗口内更新 lastGoodCamera（用户合法手势把相机带到新位置后，
    // 后续回弹应回到手势终点而非旧目标）
    if let t = json["target"] as? [Double], t.count == 2,
      !isImplausibleCameraTarget(lat: t[0], lng: t[1], zoom: dbl(json["zoom"]) ?? 0) {
      lastGoodCamera = (
        target: CLLocationCoordinate2D(latitude: t[0], longitude: t[1]),
        zoom: CGFloat(dbl(json["zoom"]) ?? 10),
        bearing: CGFloat(dbl(json["bearing"]) ?? 0),
        tilt: CGFloat(dbl(json["tilt"]) ?? 0)
      )
    }
    fixSnapbackIfWorldCorner(json)
    notifyDart("cameraMoveEnd", json)
  }

  /// 地图区域变化过程中持续回调（官方用 mapViewRegionChanged 上报 camera#onMove）。
  /// SDK 11.x 在 iOS 26 上存在 region 空转：连发载荷完全相同的回调
  /// （真机日志 2026-11-03），lastCameraMovePayload 去重后对 Dart 只透传变化值。
  public func mapViewRegionChanged(_ mapView: MAMapView) {
    let cc = mapView.centerCoordinate
    let zoom = Double(mapView.zoomLevel)
    let bearing = Double(mapView.rotationDegree)
    let tilt = Double(mapView.cameraDegree)
    if let last = lastCameraMove,
      last.lat == cc.latitude, last.lng == cc.longitude,
      last.zoom == zoom, last.bearing == bearing, last.tilt == tilt {
      return
    }
    lastCameraMove = (cc.latitude, cc.longitude, zoom, bearing, tilt)
    AMapLog.d("map#\(mapId) cameraMove")
    notifyDart("cameraMove", cameraJson())
  }

  /// 单击地图（SDK 11.x 委托方法名为 didSingleTappedAt）
  public func mapView(_ mapView: MAMapView, didSingleTappedAt coordinate: CLLocationCoordinate2D) {
    AMapLog.d("map#\(mapId) mapTap \(coordinate.latitude), \(coordinate.longitude)")
    notifyDart("mapTap", [coordinate.latitude, coordinate.longitude])
  }

  /// 长按事件（SDK 11.x 委托方法名为 didLongPressedAt）
  public func mapView(_ mapView: MAMapView, didLongPressedAt coordinate: CLLocationCoordinate2D) {
    AMapLog.d("map#\(mapId) mapLongPress \(coordinate.latitude), \(coordinate.longitude)")
    notifyDart("mapLongPress", [coordinate.latitude, coordinate.longitude])
  }

  /// mapLoaded 是否已回发过（见主类属性区 didNotifyMapLoaded 注释）。
  public func mapViewDidFinishLoadingMap(_ mapView: MAMapView) {
    guard !didNotifyMapLoaded else { return }
    didNotifyMapLoaded = true
    AMapLog.d("map#\(mapId) mapLoaded（底图首帧就绪）")
    resyncOverlaysIfRendererNeverRequested()
    // 重试挂起的气泡补选（地图初始化期间 selectAnnotation 被忽略的场景）
    retryPendingSelections()
    // 二次校正（跳变重绘）：mapInitComplete 时的 setMapStatus 可能只改了
    // 逻辑状态、渲染管线未跟随（点击/瓦片仍在世界原点角 → 蓝屏）。底图首帧
    // 就绪后重设一次初始相机，用相机跳变强制渲染管线重绘（替代已移除的
    // limitMapRect workaround）。例外：用户已手势移动过相机则跳过（见下方
    // userMoved 守卫）。未配置相机时 SDK 默认中心本就是北京，跳过即可。
    if let cam = lastInitialCamera {
      // 跳过守卫：用户在 mapLoaded 前已通过手势把相机移离初始目标时，
      // 无条件重设会把手势结果拉回初始位置。判定依据 lastGoodCamera（
      // regionDidChange 持续更新，合法落点）与初始目标的 map point 距离
      // 超过一个视口宽。渲染管线未跟随的蓝屏场景不受影响 —— 那时
      // regionDidChange 上报的是逻辑状态，lastGoodCamera 仍等于初始目标。
      let userMoved =
        lastGoodCamera.map {
          mapPointDistance($0.target, cam.target)
            > Double(mapView.visibleMapRect.size.width)
        } ?? false
      if userMoved {
        AMapLog.d("map#\(mapId) mapLoaded 前用户已移动相机，跳过初始相机重设")
      } else {
        AMapLog.d("map#\(mapId) mapLoaded 后重设初始相机（强制渲染重绘）")
        applyInitialCameraNow(
          target: cam.target, zoom: cam.zoom, bearing: cam.bearing, tilt: cam.tilt)
      }
    }
    notifyDart("mapLoaded", nil)
  }

  /// 两坐标间的 map point 距离（世界投影坐标，与缩放级别无关）。
  private func mapPointDistance(
    _ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D
  ) -> Double {
    let pa = MAMapPointForCoordinate(a)
    let pb = MAMapPointForCoordinate(b)
    let dx = Double(pa.x - pb.x)
    let dy = Double(pa.y - pb.y)
    return (dx * dx + dy * dy).squareRoot()
  }

  /// iOS 26（4× 坐标基准）实测：create 阶段（mapInitComplete 之前）添加的
  /// overlay 永远不会触发 rendererFor 委托回调（同一时段 marker 的 viewFor
  /// 正常工作），线/面/圆因此完全不渲染。此处跟踪 rendererFor 是否被调用过，
  /// 首次 mapLoaded 时若从未触发，则 remove+add 重加全部覆盖物强制其重新
  /// 入渲染队列 —— 一旦 rendererFor 被调用过即跳过，正常系统零开销。
  private func resyncOverlaysIfRendererNeverRequested() {
    guard !didResyncOverlays, !overlayRendererRequested else { return }
    didResyncOverlays = true
    // MAOverlay 继承自 MAAnnotation，数组重载存在二义性，统一走单个 add/remove
    // （与 addPolyline 等既有路径一致）
    let polylines = Array(polylinesById.values)
    let polygons = Array(polygonsById.values)
    let circles = Array(circlesById.values)
    guard !polylines.isEmpty || !polygons.isEmpty || !circles.isEmpty else { return }
    AMapLog.d(
      "map#\(mapId) rendererFor 从未触发，mapLoaded 后重加覆盖物"
        + "（polyline=\(polylines.count) polygon=\(polygons.count) circle=\(circles.count)）")
    for overlay in polylines {
      mapView.remove(overlay)
      mapView.add(overlay)
    }
    for overlay in polygons {
      mapView.remove(overlay)
      mapView.add(overlay)
    }
    for overlay in circles {
      mapView.remove(overlay)
      mapView.add(overlay)
    }
  }

  // ---- Marker 视图 ----

  public func mapView(_ mapView: MAMapView, viewFor annotation: MAAnnotation) -> MAAnnotationView? {
    guard let marker = annotation as? QsMarker else {
      AMapLog.d("map#\(mapId) viewFor：非 QsMarker 注解 \(type(of: annotation))，交由 SDK 默认处理")
      return nil
    }
    markerViewsCreated.insert(marker.customId)
    let image = qsImage(from: marker.json["icon"], screenScale: screenScale)
    if image == nil, let icon = marker.json["icon"] {
      // 注意：defaultMarker 类型走 SDK 默认大头针属正常回退，此处仅提示
      AMapLog.d("map#\(mapId) marker id=\(marker.customId) 图标解码为 nil，回退 SDK 大头针 icon=\(icon)")
    }
    // 与官方一致使用复用标识，复用后逐项重设属性。
    // 自定义图标与默认大头针分池复用，避免带图视图被复用给无图 marker。
    let hasCustomIcon = image != nil
    let reuseId = hasCustomIcon ? "qs_marker_image" : "qs_marker_pin"
    let view: MAAnnotationView
    if let reused = mapView.dequeueReusableAnnotationView(withIdentifier: reuseId) {
      view = reused
    } else if hasCustomIcon {
      view = MAAnnotationView(annotation: marker, reuseIdentifier: reuseId)
    } else {
      // 无自定义图标时使用 SDK 自带大头针
      view = MAPinAnnotationView(annotation: marker, reuseIdentifier: reuseId)
    }
    view.annotation = marker
    // 仅在有自定义图标时设置 image：
    // MAPinAnnotationView 的默认大头针依赖内部 image，无条件赋 nil 会把默认图
    // 清掉 → 视图尺寸变 0×0 → marker 隐身（初始 marker 不显示的根因）
    if let image {
      view.image = image
    } else if let pin = view as? MAPinAnnotationView {
      // defaultMarkerWithHue：iOS 仅提供红/绿/紫三种大头针色，按色相就近映射
      // （0°红 / 120°绿 / 300°紫）
      if let icon = marker.json["icon"] as? [String: Any],
        icon["type"] as? String == "defaultMarkerWithHue",
        let hue = icon["hue"] as? Double {
        pin.pinColor = hue < 60 || hue >= 300 ? .red : (hue < 180 ? .green : .purple)
      } else {
        pin.pinColor = .red
      }
    }
    view.isEnabled = (marker.json["clickable"] as? Bool) ?? true
    view.isDraggable = (marker.json["draggable"] as? Bool) ?? false
    view.isHidden = !((marker.json["visible"] as? Bool) ?? true)
    // alpha / zIndex / rotation：复用池出来的视图必须无条件重置为本次
    // 配置（字段缺省用默认值），否则残留上一轮 marker 的属性 —— 实测复用
    // 带旋转/半透明视图给普通 marker 时旋转与透明度会串味。
    // alpha / zIndex：MAAnnotationView 直接属性（官方插件在用）
    view.alpha = CGFloat((marker.json["alpha"] as? Double) ?? 1)
    view.zIndex = Int((marker.json["zIndex"] as? Double) ?? 0)
    // rotation：iOS 无 rotation 属性，官方用 imageView 旋转变换实现
    if let rotation = marker.json["rotation"] as? Double {
      view.imageView.transform = CGAffineTransform(
        rotationAngle: CGFloat(rotation) / 180.0 * .pi)
    } else {
      view.imageView.transform = .identity
    }

    let infoWindow = marker.json["infoWindow"] as? [String: Any]
    // infoWindowEnable=false 时禁用气泡（对齐 Android 行为）
    let infoWindowEnabled = (marker.json["infoWindowEnable"] as? Bool) ?? true
    // 气泡内容是否非空：title / snippet / 自定义 content 三者任一非空
    // （不能判字典 isEmpty —— toJson 恒有 4 个键，字典永不为空）
    let hasBubbleContent: Bool = {
      guard let info = infoWindow else { return false }
      let title = (info["title"] as? String)?.isEmpty == false
      let snippet = (info["snippet"] as? String)?.isEmpty == false
      let hasContent = qsImage(from: info["content"], screenScale: screenScale) != nil
      return title || snippet || hasContent
    }()
    // 自定义气泡：Widget 截图替换整个 callout
    if let calloutImage = qsImage(from: infoWindow?["content"], screenScale: screenScale) {
      view.canShowCallout = infoWindowEnabled
      let imageView = UIImageView(image: calloutImage)
      // 官方初始化器为 initWithCustomView:（单数，自 SDK 5.0.0）
      view.customCalloutView = MACustomCalloutView(customView: imageView)
    } else {
      // 复用自带 content 气泡的视图时必须清掉旧 customCalloutView，
      // 否则本 marker（无 content）选中时会弹出上一个 marker 的气泡截图
      view.customCalloutView = nil
      view.canShowCallout = infoWindowEnabled && hasBubbleContent
    }

    // 锚点：Dart 约定 (0,0) 左上 (1,1) 右下；iOS annotationView 中心默认位于
    // 坐标点（等价锚点 0.5,0.5），官方换算为 offset = size * (0.5 - anchor)
    let anchor = marker.json["anchor"] as? [Double]
    let u = (anchor?.count ?? 0) > 0 ? anchor![0] : 0.5
    let v = (anchor?.count ?? 0) > 1 ? anchor![1] : 1.0
    let width = image?.size.width ?? view.frame.width
    let height = image?.size.height ?? view.frame.height
    view.centerOffset = CGPoint(x: width * (0.5 - u), y: height * (0.5 - v))
    // flat：官方暂不在 iOS 开放，跳过
    return view
  }

  /// annotation view 创建完成：此处补选挂起的程序化气泡（InfoWindow.show /
  /// showInfoWindow 在 view 未就绪时只能先挂起，selectAnnotation 对无 view
  /// 的 annotation 是 no-op）。
  /// 注意：vendored 头文件为不带泛型的 NSArray *，Swift 桥接为 [Any]，
  /// 声明成 [MAAnnotationView] 会导致签名不匹配、委托永不被调。
  ///
  /// 时序坑（2026-11-05 真机实测）：本委托触发时视图刚加入、布局未完成
  /// （iOS 26 尤其明显，与 create 阶段 overlay 不渲染 rendererFor 的问题
  /// 同族），此处同步 selectAnnotation 会被 SDK 静默忽略 → 气泡永不弹出，
  /// 且 programmaticSelection 残留会吞掉用户下一次真实点击。
  /// 修复：异步到下一帧再选中；若仍被忽略（地图尚未 mapInitComplete 等），
  /// 重新挂起，等 didAddAnnotationViews / mapLoaded 重试。
  public func mapView(_ mapView: MAMapView, didAddAnnotationViews views: [Any]) {
    for case let view as MAAnnotationView in views {
      guard let marker = view.annotation as? QsMarker,
            pendingShowSelection.remove(marker.customId) != nil else { continue }
      DispatchQueue.main.async { [weak self] in
        guard let self, !self.disposed else { return }
        // 异步执行前 marker 可能已被移除（remove+add 差量更新竞态）
        guard self.markersById[marker.customId] === marker else { return }
        // 用户已抢先手动选中（或已选中）则无需补选
        if self.mapView.selectedAnnotations.contains(where: {
          ($0 as? QsMarker)?.customId == marker.customId
        }) {
          AMapLog.d("map#\(self.mapId) 补选跳过：id=\(marker.customId) 已选中")
          return
        }
        self.programmaticSelection.insert(marker.customId)
        self.mapView.selectAnnotation(marker, animated: false)
        if self.mapView.selectedAnnotations.contains(where: {
          ($0 as? QsMarker)?.customId == marker.customId
        }) {
          AMapLog.d("map#\(self.mapId) 补选气泡 id=\(marker.customId)（didAddAnnotationViews→async）")
        } else {
          // 地图未就绪等场景选中仍被忽略：重新挂起等待重试
          self.pendingShowSelection.insert(marker.customId)
          AMapLog.d("map#\(self.mapId) 补选被忽略，重新挂起 id=\(marker.customId)")
        }
      }
    }
  }

  /// 地图就绪后重试挂起的气泡补选：覆盖「view 早已创建、但当时地图未完成
  /// 初始化导致 selectAnnotation 被忽略」的场景（didAddAnnotationViews 只在
  /// 新视图加入时触发，view 已存在时不会再来）。view 未创建的保持挂起，
  /// 由后续 didAddAnnotationViews 补选。
  private func retryPendingSelections() {
    guard !pendingShowSelection.isEmpty, !disposed else { return }
    // 快照遍历：循环体内会 remove 命中项，直接遍历 Set 属于遍历中变更
    for id in Array(pendingShowSelection) {
      guard let marker = markersById[id], markerViewsCreated.contains(id) else { continue }
      programmaticSelection.insert(id)
      mapView.selectAnnotation(marker, animated: false)
      if mapView.selectedAnnotations.contains(where: { ($0 as? QsMarker)?.customId == id }) {
        pendingShowSelection.remove(id)
        AMapLog.d("map#\(mapId) mapLoaded 重试补选成功 id=\(id)")
      } else {
        programmaticSelection.remove(id)
        AMapLog.d("map#\(mapId) mapLoaded 重试补选仍被忽略 id=\(id)")
      }
    }
  }

  public func mapView(_ mapView: MAMapView, didSelect view: MAAnnotationView) {
    if let marker = view.annotation as? QsMarker {
      // 程序化选中（InfoWindow.show）不回发 markerTap，避免误报用户点击
      if programmaticSelection.remove(marker.customId) != nil {
        AMapLog.d("map#\(mapId) didSelect id=\(marker.customId)（程序化选中，抑制回发）")
        return
      }
      AMapLog.d("map#\(mapId) markerTap id=\(marker.customId)")
      notifyDart("markerTap", marker.customId)
    }
  }

  public func mapView(
    _ mapView: MAMapView,
    annotationView view: MAAnnotationView,
    didChange newState: MAAnnotationViewDragState,
    fromOldState oldState: MAAnnotationViewDragState
  ) {
    switch newState {
    case .starting, .dragging:
      startDragTracking(view)
    case .canceling:
      stopDragTracking()
    case .ending:
      stopDragTracking()
      guard let marker = view.annotation as? QsMarker else { return }
      // SDK 拖拽期间视图中心跟手（不考虑锚点），松手时按「视图中心」算落点；
      // 用户瞄准的是锚点（如大头针针尖，在视图内底部），落点因此系统性偏离
      // 半个锚距。且 .ending 到达时视图已被摆回静止位（坐标+offset），无法从
      // 当前 view.center 还原松手瞬间位置——用拖拽期间逐帧采样的最后一帧：
      // 锚点屏幕位置 = view.center - centerOffset（对任意锚点/任意时刻成立，
      // 因为 centerOffset 只影响视图摆放、不影响图在视图内的布局）。
      let center = dragLastCenter ?? view.center
      let offset = dragLastCenterOffset ?? view.centerOffset
      let oldCoord = marker.coordinate
      let anchorPoint = CGPoint(x: center.x - offset.x, y: center.y - offset.y)
      marker.coordinate = mapView.convert(anchorPoint, toCoordinateFrom: mapView)
      AMapLog.d(
        "map#\(mapId) markerDragEnd id=\(marker.customId) 落点校正 "
          + "old=(\(oldCoord.latitude), \(oldCoord.longitude)) "
          + "new=(\(marker.coordinate.latitude), \(marker.coordinate.longitude))")
      notifyDart(
        "markerDragEnd",
        [
          "id": marker.customId,
          "position": [marker.coordinate.latitude, marker.coordinate.longitude],
        ])
    default:
      break
    }
  }

  /// 拖拽期间逐帧采样视图位置（CADisplayLink）：
  /// .ending 时 SDK 已重摆视图，只有采样能拿到松手瞬间的 center/centerOffset。
  private func startDragTracking(_ view: MAAnnotationView) {
    dragTrackView = view
    dragLastCenter = nil
    dragLastCenterOffset = nil
    guard dragTrackLink == nil else { return }
    let link = CADisplayLink(target: self, selector: #selector(dragTrackTick))
    link.add(to: .main, forMode: .common)
    dragTrackLink = link
  }

  private func stopDragTracking() {
    dragTrackLink?.invalidate()
    dragTrackLink = nil
  }

  @objc private func dragTrackTick() {
    guard let view = dragTrackView else { return }
    dragLastCenter = view.center
    dragLastCenterOffset = view.centerOffset
  }

  /// 气泡（InfoWindow）点击 → infoWindowTap（载荷与 Android 一致：marker id）。
  ///
  /// 注意 SDK 限制（5.0.0 起）：MACustomCalloutView 自定义气泡（Dart Widget
  /// 截图模式）**不会**触发此回调 —— 与 Android 的自定义气泡行为差异，
  /// 业务侧若需自定义气泡点击请改用 markerTap。
  public func mapView(_ mapView: MAMapView, didAnnotationViewCalloutTapped view: MAAnnotationView) {
    guard let marker = view.annotation as? QsMarker else { return }
    AMapLog.d("map#\(mapId) infoWindowTap id=\(marker.customId)")
    notifyDart("infoWindowTap", marker.customId)
  }

  /// 底图 POI 点击 → poiTap（载荷与 Android 一致：{id, name, position}）。
  /// didTouchPois 为数组，通常单元素；逐个转发保持与 Android 单 POI 回调语义一致。
  public func mapView(_ mapView: MAMapView, didTouchPois pois: [Any]) {
    for case let poi as MATouchPoi in pois {
      // uid/name 头文件为隐式解包可选：显式兜底，避免插值告警与
      // 通道编码遇 nil 字段异常
      let uid = poi.uid ?? ""
      let name = poi.name ?? ""
      AMapLog.d("map#\(mapId) poiTap uid=\(uid) name=\(name)")
      notifyDart(
        "poiTap",
        [
          "id": uid,
          "name": name,
          "position": [poi.coordinate.latitude, poi.coordinate.longitude],
        ])
    }
  }

  // ---- 覆盖物渲染器 ----

  public func mapView(_ mapView: MAMapView, rendererFor overlay: MAOverlay) -> MAOverlayRenderer? {
    overlayRendererRequested = true
    switch overlay {
    case let polyline as QsPolyline:
      // SDK 11.2 起 renderer 初始化器为可失败（setPolyline 可能失败）
      guard let renderer = MAPolylineRenderer(polyline: polyline) else {
        AMapLog.d("map#\(mapId) MAPolylineRenderer 创建失败 id=\(polyline.customId)")
        return nil
      }
      renderer.lineWidth = (polyline.json["width"] as? CGFloat) ?? 10
      let stroke = color(
        polyline.json["color"], fallback: UIColor(red: 0, green: 0, blue: 1, alpha: 0.8))
      // Dart 侧独立的 alpha 字段与颜色 ARGB 相乘
      let alpha = (polyline.json["alpha"] as? Double) ?? 1
      renderer.strokeColor =
        alpha >= 1 ? stroke : stroke.withAlphaComponent(CGFloat(alpha) * stroke.cgColor.alpha)
      // 虚线：MALineDashType 只有 none / square / dot（无 .dash；dash/dashDot → square）
      switch polyline.json["dashLineType"] as? String {
      case "dash", "dashDot": renderer.lineDashType = kMALineDashTypeSquare
      case "dot": renderer.lineDashType = kMALineDashTypeDot
      default: renderer.lineDashType = kMALineDashTypeNone
      }
      // 线帽（对齐 Android LineCapType，iOS 完整支持含箭头）
      switch polyline.json["capType"] as? String {
      case "round": renderer.lineCapType = kMALineCapRound
      case "square": renderer.lineCapType = kMALineCapSquare
      case "arrow": renderer.lineCapType = kMALineCapArrow
      default: renderer.lineCapType = kMALineCapButt
      }
      // 连接样式（对齐 Android LineJoinType）
      switch polyline.json["joinType"] as? String {
      case "bevel": renderer.lineJoinType = kMALineJoinBevel
      case "round": renderer.lineJoinType = kMALineJoinRound
      default: renderer.lineJoinType = kMALineJoinMiter
      }
      // 自定义纹理线（对齐 Android setCustomTexture）：strokeImage 直接接受 UIImage，
      // 设置后纹理覆盖 strokeColor（与 Android 行为一致）。
      // 官方约定：纹理图建议正方形且边长为 2 的次幂（GLES 约束，Metal 渲染下较宽松）。
      if let texture = qsImage(from: polyline.json["customTexture"], screenScale: screenScale) {
        renderer.strokeImage = texture
      }
      AMapLog.d(
        "map#\(mapId) rendererFor polyline id=\(polyline.customId)"
          + " texture=\(renderer.strokeImage != nil ? "已设" : "无")"
          + " cap=\(polyline.json["capType"] ?? "-")")
      return renderer
    case let polygon as QsPolygon:
      guard let renderer = MAPolygonRenderer(polygon: polygon) else {
        AMapLog.d("map#\(mapId) MAPolygonRenderer 创建失败 id=\(polygon.customId)")
        return nil
      }
      renderer.lineWidth = (polygon.json["strokeWidth"] as? CGFloat) ?? 10
      renderer.strokeColor = color(
        polygon.json["strokeColor"], fallback: UIColor.black.withAlphaComponent(0.8))
      let hollow = (polygon.json["hollow"] as? Bool) ?? false
      renderer.fillColor =
        hollow
        ? UIColor.clear
        : color(polygon.json["fillColor"], fallback: UIColor.clear)
      return renderer
    case let circle as QsCircle:
      guard let renderer = MACircleRenderer(circle: circle) else {
        AMapLog.d("map#\(mapId) MACircleRenderer 创建失败 id=\(circle.customId)")
        return nil
      }
      renderer.lineWidth = (circle.json["strokeWidth"] as? CGFloat) ?? 10
      renderer.strokeColor = color(
        circle.json["strokeColor"], fallback: UIColor.black.withAlphaComponent(0.8))
      renderer.fillColor = color(circle.json["fillColor"], fallback: UIColor.clear)
      return renderer
    default:
      AMapLog.d("map#\(mapId) rendererFor：未知 overlay 类型 \(type(of: overlay))，不渲染")
      return nil
    }
  }
}

// MARK: - 序列化辅助

extension CLLocationCoordinate2D {
  func toJsonList() -> [Double] {
    [latitude, longitude]
  }
}

/// 图标解码缓存：大量 Marker（几百~几千）共用同一图标时，避免每个
/// annotation view 构建/每次 addMarker 检查都重新解码 UIImage。
/// key：asset 路径 / bytes 内容 MD5；上限 64 条（LRU）。
private let qsImageCache: NSCache<NSString, UIImage> = {
  let cache = NSCache<NSString, UIImage>()
  cache.countLimit = 64
  return cache
}()

/// bytes 图标的缓存 key：内容 MD5（非加密用途，防碰撞足够）。
private func qsBytesKey(_ data: Data) -> NSString {
  let digest = Insecure.MD5.hash(data: data)
  let hex = digest.map { String(format: "%02x", $0) }.joined()
  return "bytes:\(hex)" as NSString
}

/// 显示像素比兜底：未显式传入时取 UITraitCollection.current（取不到时按 1，
/// 最坏结果是图标按 1x 解释略糊，不出错）。替代已弃用的 UIScreen.main.scale。
private func qsEffectiveScale(_ screenScale: CGFloat) -> CGFloat {
  if screenScale > 0 { return screenScale }
  let current = UITraitCollection.current.displayScale
  return current > 0 ? current : 1
}

/// 从 icon JSON 构建 UIImage（带缓存）。
///
/// `defaultMarker` / `defaultMarkerWithHue` 返回 nil，由调用方回退到
/// SDK 自带大头针（iOS 无 Android 色相着色等价 API）；
/// `asset` / `assetImage` 支持带分辨率目录前缀的路径。
func qsImage(from json: Any?, screenScale: CGFloat = 0) -> UIImage? {
  guard let map = json as? [String: Any] else { return nil }
  switch map["type"] as? String {
  case "asset", "assetImage":
    guard var asset = map["asset"] as? String else {
      AMapLog.d("qsImage：asset 类型缺少 asset 字段")
      return nil
    }
    // 去除分辨率目录前缀（如 "2.0x/"）
    if let range = asset.range(of: #"^\d+(\.\d+)?x/"#, options: .regularExpression) {
      asset = String(asset[range.upperBound...])
    }
    let width = map["width"] as? Double
    let height = map["height"] as? Double
    // 缓存键必须含目标尺寸：同路径不同尺寸互相污染
    let key = "asset:\(asset):\(width ?? 0):\(height ?? 0)" as NSString
    if let cached = qsImageCache.object(forKey: key) { return cached }
    let lookupKey = FlutterDartProject.lookupKey(forAsset: asset)
    guard let path = Bundle.main.path(forResource: lookupKey, ofType: nil) else {
      AMapLog.d("qsImage：asset 文件未找到 \(asset)（检查 pubspec.yaml 是否声明并重新构建）")
      return nil
    }
    guard let image = UIImage(contentsOfFile: path) else {
      AMapLog.d("qsImage：asset 解码失败 \(asset)")
      return nil
    }
    let finalImage =
      qsResizedImage(image, width: width, height: height, screenScale: screenScale)
      ?? image
    qsImageCache.setObject(finalImage, forKey: key)
    return finalImage
  case "bytes":
    guard let bytes = map["bytes"] as? FlutterStandardTypedData else {
      AMapLog.d("qsImage：bytes 类型数据缺失或类型不符（实际: \(type(of: map["bytes"]))）")
      return nil
    }
    let width = map["width"] as? Double
    let height = map["height"] as? Double
    // 缓存键必须含目标尺寸：同字节不同尺寸互相污染
    let key =
      "bytes:\(qsBytesKey(bytes.data)):\(width ?? -1):\(height ?? -1)"
      as NSString
    if let cached = qsImageCache.object(forKey: key) { return cached }
    guard let raw = UIImage(data: bytes.data) else {
      AMapLog.d("qsImage：bytes 解码失败（\(bytes.data.count) 字节）")
      return nil
    }
    // UIImage(data:) 默认 scale=1，会把 PNG 物理像素当点显示——
    // pixelRatio 3 渲染的 Widget 快照因此放大 3 倍（超出屏幕）。
    // 指定逻辑尺寸时按 物理像素/逻辑点 求正确的 scale（单 scale 等比，
    // 宽高同时指定且比例不符时以宽为准）；未指定时按屏幕像素比解释，
    // 与 Android 的 px→dp 视觉一致。
    let image: UIImage
    if let logical = width ?? height {
      let logicalWidth = width ?? logical * raw.size.width / max(raw.size.height, 0.001)
      let scale = raw.size.width * raw.scale / max(logicalWidth, 0.001)
      image = UIImage(data: bytes.data, scale: scale) ?? raw
    } else {
      image = UIImage(data: bytes.data, scale: qsEffectiveScale(screenScale)) ?? raw
    }
    qsImageCache.setObject(image, forKey: key)
    return image
  default:
    // defaultMarker / defaultMarkerWithHue / 未知类型 → SDK 默认大头针
    return nil
  }
}

/// 将图片缩放到目标逻辑点尺寸（fromIconPath 的 width/height）。
///
/// 只给其一时另一边按原图宽高比推导；width/height 均为 nil 返回 nil（调用方
/// 保留原图）。输出按屏幕物理分辨率渲染（format.scale），保证显示清晰。
func qsResizedImage(
  _ image: UIImage, width: Double?, height: Double?, screenScale: CGFloat = 0
) -> UIImage? {
  guard width != nil || height != nil, image.size.width > 0, image.size.height > 0
  else { return nil }
  let aspect = image.size.width / image.size.height
  var target = CGSize.zero
  if let width, let height {
    target = CGSize(width: width, height: height)
  } else if let width {
    target = CGSize(width: width, height: width / aspect)
  } else if let height {
    target = CGSize(width: height * aspect, height: height)
  }
  let format = UIGraphicsImageRendererFormat.default()
  format.scale = qsEffectiveScale(screenScale)
  format.opaque = false
  let renderer = UIGraphicsImageRenderer(size: target, format: format)
  return renderer.image { _ in
    image.draw(in: CGRect(origin: .zero, size: target))
  }
}
