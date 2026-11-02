import AMap3DMap
import CryptoKit
import Flutter
import Foundation
import UIKit

/// 地图 PlatformView 工厂。creationParams 由 Dart 侧 AMapWidget 传入。
public class AMapPlatformViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  public func createArgsCodec() -> FlutterMessageCodec & NSObject {
    FlutterStandardMessageCodec.sharedInstance()
  }

  public func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    let params = args as? [String: Any] ?? [:]
    return AMapPlatformView(
      frame: frame, messenger: messenger, creationParams: params)
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
    if holes.isEmpty {
      super.init(coordinates: coordinates, count: coordinates.count)
    } else {
      let interior = holes.map { MAPolygon(coordinates: $0, count: $0.count) }
      super.init(
        coordinates: coordinates,
        count: coordinates.count,
        interiorPolygons: interior)
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
/// 每个实例持有独立通道 `amap_maps_flutter_qs/map#<mapId>`，
/// mapId 由 Dart 侧通过 creationParams 传入，保证两端一致。
///
/// 覆盖物同步：与 Android 端一致，Dart 侧差量 diff 后下发
/// `toAdd / toUpdate / toRemove`；update 一律「删旧 + 建新」。
///
/// 相机操作使用 iOS SDK 的 `MAMapStatus` + `setMapStatus:animated:duration:`
/// 体系（与官方 amap_flutter_map 一致）；iOS SDK 无 MACameraUpdate/MACameraPosition。
public class AMapPlatformView: NSObject, FlutterPlatformView {
  private let mapId: Int
  private let mapView: MAMapView
  private let channel: FlutterMethodChannel
  private var disposed = false

  private var markersById: [String: QsMarker] = [:]
  private var polylinesById: [String: QsPolyline] = [:]
  private var polygonsById: [String: QsPolygon] = [:]
  private var circlesById: [String: QsCircle] = [:]
  // 程序化选中（InfoWindow.show）期间的 didSelect 抑制表
  private var programmaticSelection = Set<String>()

  init(frame: CGRect, messenger: FlutterBinaryMessenger, creationParams: [String: Any]) {
    mapId = (creationParams["mapId"] as? Int) ?? -1
    mapView = MAMapView(frame: frame)
    channel = FlutterMethodChannel(
      name: "\(AmapMapsFlutterQsPlugin.mainChannelName)/map#\(mapId)",
      binaryMessenger: messenger)
    super.init()

    channel.setMethodCallHandler(handleMapMethod)
    applyInitialOptions(creationParams)
    notifyDartMapCreated()
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

    // 缩放范围：iOS SDK 为独立属性 minZoomLevel / maxZoomLevel
    if let minZoom = params["minZoom"] as? Double {
      mapView.minZoomLevel = CGFloat(minZoom)
    }
    if let maxZoom = params["maxZoom"] as? Double {
      mapView.maxZoomLevel = CGFloat(maxZoom)
    }

    // 定位蓝点
    mapView.showsUserLocation = (params["myLocationEnabled"] as? Bool) ?? false
    // TODO(MVP): myLocationStyle（MAUserLocationRepresentation）与 customStyle 的 iOS 对接

    // 手势开关（US-04）
    applyGestures(params["gestures"])

    // UI 开关（路况/POI 点击/建筑物/标注/指南针/比例尺）
    applyUiOptions(params["uiOptions"])

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
      mapView.showTraffic = traffic
    }
    if let touchPoi = options["touchPoiEnabled"] as? Bool {
      mapView.touchPOIEnabled = touchPoi
    }
    if let buildings = options["buildingsEnabled"] as? Bool {
      mapView.showsBuildings = buildings
    }
    if let labels = options["labelsEnabled"] as? Bool {
      mapView.showsLabels = labels
    }
    if let compass = options["compassEnabled"] as? Bool {
      mapView.showsCompass = compass
    }
    if let scale = options["scaleEnabled"] as? Bool {
      mapView.showsScale = scale
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
    if let rect = mapRect(fromBoundsJson: json) {
      mapView.limitMapRect = rect
    } else {
      // null → 解除限制
      mapView.limitMapRect = MAMapRectMake(0, 0, 0, 0)
    }
  }

  private func applyCameraPosition(_ json: [String: Any]) {
    guard let target = jsonToLatLng(json["target"]) else { return }
    var status = currentMapStatus()
    status.centerCoordinate = target
    status.zoomLevel = CGFloat((json["zoom"] as? Double) ?? 10)
    status.cameraDegree = CGFloat((json["tilt"] as? Double) ?? 0)
    status.rotationDegree = CGFloat((json["bearing"] as? Double) ?? 0)
    mapView.setMapStatus(status, animated: false, duration: 0)
  }

  /// 取当前地图状态；getMapStatus 正常情况下非空，兜底用官方指定初始化器构造。
  private func currentMapStatus() -> MAMapStatus {
    mapView.getMapStatus()
      ?? MAMapStatus(
        centerCoordinate: CLLocationCoordinate2D(latitude: 39.909187, longitude: 116.397451),
        zoomLevel: 10, rotationDegree: 0, cameraDegree: 0,
        screenAnchor: CGPoint(x: 0.5, y: 0.5))
  }

  private func bindMapEvents() {
    mapView.delegate = self
  }

  // ---- 覆盖物构建 ----

  private func addMarker(_ json: [String: Any]) {
    guard let id = json["id"] as? String, markersById[id] == nil,
      let position = jsonToLatLng(json["position"])
    else { return }
    let marker = QsMarker(customId: id, json: json)
    marker.coordinate = position
    var showOnCreate = false
    if let info = json["infoWindow"] as? [String: Any] {
      marker.title = info["title"] as? String
      marker.subtitle = info["snippet"] as? String
      // content 模式（Widget 截图气泡）：title/subtitle 兜底非空 ——
      // annotation 无 title 时点击选中不弹 callout（与 Android SDK 约定一致）。
      // 用零宽空格占位：不可见，且不会被非空校验的 trim 判为空
      if qsImage(from: info["content"]) != nil {
        if marker.title == nil { marker.title = "\u{200B}" }
        if marker.subtitle == nil { marker.subtitle = "\u{200B}" }
      }
      showOnCreate = info["show"] == true
    }
    markersById[id] = marker
    mapView.add(marker)
    // 默认显示气泡（InfoWindow.show）
    if showOnCreate {
      programmaticSelection.insert(id)
      mapView.selectedAnnotations = [marker]
    }
  }

  private func addPolyline(_ json: [String: Any]) {
    guard let id = json["id"] as? String, polylinesById[id] == nil,
      let points = jsonToLatLngList(json["points"]), points.count >= 2
    else { return }
    let polyline = QsPolyline(customId: id, json: json)
    polyline.setCoordinates(points, count: points.count)
    polylinesById[id] = polyline
    mapView.add(polyline)
  }

  private func addPolygon(_ json: [String: Any]) {
    guard let id = json["id"] as? String, polygonsById[id] == nil,
      let points = jsonToLatLngList(json["points"]), points.count >= 3
    else { return }
    let holes = (json["holes"] as? [[Any]])?.compactMap(jsonToLatLngList) ?? []
    let polygon = QsPolygon(
      customId: id, json: json, coordinates: points, holes: holes)
    polygonsById[id] = polygon
    mapView.add(polygon)
  }

  private func addCircle(_ json: [String: Any]) {
    guard let id = json["id"] as? String, circlesById[id] == nil,
      let center = jsonToLatLng(json["center"])
    else { return }
    let radius = (json["radius"] as? Double) ?? 0
    let circle = QsCircle(customId: id, json: json)
    circle.coordinate = center
    circle.radius = radius
    circlesById[id] = circle
    mapView.add(circle)
  }

  private func removeMarker(_ id: String) {
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
    guard let map = payload as? [String: Any] else { return }
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
        mapView.selectAnnotation(marker, animated: false)
      }
      result(nil)

    case "map#hideInfoWindow":
      if let id = call.arguments as? String, let marker = markersById[id] {
        mapView.deselectAnnotation(marker, animated: false)
      }
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// 应用相机更新（iOS SDK 无 MACameraUpdate，统一走 MAMapStatus；
  /// bounds 适配走 setVisibleMapRect:edgePadding:animated:，与官方一致）。
  private func applyCameraUpdate(_ payload: Any?, animated: Bool, duration: CFTimeInterval) {
    guard let json = payload as? [String: Any] else { return }
    switch json["op"] as? String {
    case "newLatLng":
      guard let target = jsonToLatLng(json["latLng"]) else { return }
      var status = currentMapStatus()
      status.centerCoordinate = target
      mapView.setMapStatus(status, animated: animated, duration: duration)
    case "newLatLngZoom":
      guard let target = jsonToLatLng(json["latLng"]), let zoom = json["zoom"] as? Double
      else { return }
      var status = currentMapStatus()
      status.centerCoordinate = target
      status.zoomLevel = CGFloat(zoom)
      mapView.setMapStatus(status, animated: animated, duration: duration)
    case "newCameraPosition":
      guard let pos = json["cameraPosition"] as? [String: Any],
        let target = jsonToLatLng(pos["target"])
      else { return }
      var status = currentMapStatus()
      status.centerCoordinate = target
      status.zoomLevel = CGFloat((pos["zoom"] as? Double) ?? 10)
      status.cameraDegree = CGFloat((pos["tilt"] as? Double) ?? 0)
      status.rotationDegree = CGFloat((pos["bearing"] as? Double) ?? 0)
      mapView.setMapStatus(status, animated: animated, duration: duration)
    case "newLatLngBounds":
      guard let rect = mapRect(fromBoundsJson: json["bounds"]) else { return }
      let padding = (json["padding"] as? Double) ?? 0
      let inset = UIEdgeInsets(top: padding, left: padding, bottom: padding, right: padding)
      mapView.setVisibleMapRect(rect, edgePadding: inset, animated: animated)
    case "zoomTo":
      guard let zoom = json["zoom"] as? Double else { return }
      var status = currentMapStatus()
      status.zoomLevel = CGFloat(zoom)
      mapView.setMapStatus(status, animated: animated, duration: duration)
    case "zoomIn", "zoomOut", "zoomBy", "zoomByFocus":
      // iOS SDK 无 zoomBy(delta)/focus 等价 API，统一按 zoomLevel ± delta 近似
      // （官方插件对 zoomIn/zoomOut 同样是 zoomLevel ± 1；focus 暂不支持）。
      let delta: Double
      switch json["op"] as? String {
      case "zoomIn": delta = 1
      case "zoomOut": delta = -1
      default: delta = (json["amount"] as? Double) ?? 0
      }
      var status = currentMapStatus()
      status.zoomLevel = status.zoomLevel + CGFloat(delta)
      mapView.setMapStatus(status, animated: animated, duration: duration)
    case "scrollBy":
      // 与官方一致：屏幕像素偏移 → 中心点经纬度换算（除以屏幕 scale）
      let dx = (json["dx"] as? Double) ?? 0
      let dy = (json["dy"] as? Double) ?? 0
      let scale = UIScreen.main.scale
      var center = mapView.center
      center.x += CGFloat(dx / scale)
      center.y += CGFloat(dy / scale)
      var status = currentMapStatus()
      status.centerCoordinate = mapView.convertPoint(center, toCoordinateFromView: mapView)
      mapView.setMapStatus(status, animated: animated, duration: duration)
    default:
      break
    }
  }

  /// 当前相机位置 JSON（键与 Dart CameraPosition.fromJson 约定一致）。
  private func cameraJson() -> [String: Any] {
    [
      "target": [mapView.centerCoordinate.latitude, mapView.centerCoordinate.longitude],
      "zoom": mapView.zoomLevel,
      "tilt": mapView.cameraDegree,
      "bearing": mapView.rotationDegree,
    ]
  }

  // ---- 生命周期 ----

  public func dispose() {
    guard !disposed else { return }
    disposed = true
    channel.setMethodCallHandler(nil)
    mapView.delegate = nil
    markersById.removeAll()
    polylinesById.removeAll()
    polygonsById.removeAll()
    circlesById.removeAll()
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
  public func mapView(_ mapView: MAMapView, regionDidChangeAnimated animated: Bool) {
    notifyDart("cameraMoveEnd", cameraJson())
  }

  /// 地图区域变化过程中持续回调（官方用 mapViewRegionChanged 上报 camera#onMove）
  public func mapViewRegionChanged(_ mapView: MAMapView) {
    notifyDart("cameraMove", cameraJson())
  }

  /// 单击地图（官方委托方法名为 didSingleTappedAtCoordinate）
  public func mapView(
    _ mapView: MAMapView, didSingleTappedAtCoordinate coordinate: CLLocationCoordinate2D
  ) {
    notifyDart("mapTap", [coordinate.latitude, coordinate.longitude])
  }

  /// 长按事件（官方委托方法名为 didLongPressedAtCoordinate）
  public func mapView(
    _ mapView: MAMapView, didLongPressedAtCoordinate coordinate: CLLocationCoordinate2D
  ) {
    notifyDart("mapLongPress", [coordinate.latitude, coordinate.longitude])
  }

  public func mapViewDidFinishLoadingMap(_ mapView: MAMapView) {
    notifyDart("mapLoaded", nil)
  }

  // ---- Marker 视图 ----

  public func mapView(_ mapView: MAMapView, viewFor annotation: MAAnnotation) -> MAAnnotationView? {
    guard let marker = annotation as? QsMarker else { return nil }
    let image = qsImage(from: marker.json["icon"])
    // 与官方一致使用共享复用标识，复用后逐项重设属性
    let reuseId = "qs_marker_annotation"
    let view: MAAnnotationView
    if let reused = mapView.dequeueReusableAnnotationView(withIdentifier: reuseId) {
      view = reused
    } else if image != nil {
      view = MAAnnotationView(annotation: marker, reuseIdentifier: reuseId)
    } else {
      // 无自定义图标时使用 SDK 自带大头针
      view = MAPinAnnotationView(annotation: marker, reuseIdentifier: reuseId)
    }
    view.annotation = marker
    view.image = image
    view.isEnabled = (marker.json["clickable"] as? Bool) ?? true
    view.isDraggable = (marker.json["draggable"] as? Bool) ?? false
    view.isHidden = !((marker.json["visible"] as? Bool) ?? true)
    // alpha / zIndex：MAAnnotationView 直接属性（官方插件在用）
    if let alpha = marker.json["alpha"] as? Double {
      view.alpha = CGFloat(alpha)
    }
    if let zIndex = marker.json["zIndex"] as? Double {
      view.zIndex = Int(zIndex)
    }
    // rotation：iOS 无 rotation 属性，官方用 imageView 旋转变换实现
    if let rotation = marker.json["rotation"] as? Double {
      view.imageView.transform = CGAffineTransform(
        rotationAngle: CGFloat(rotation) / 180.0 * .pi)
    }

    let infoWindow = marker.json["infoWindow"] as? [String: Any]
    // infoWindowEnable=false 时禁用气泡（对齐 Android 行为）
    let infoWindowEnabled = (marker.json["infoWindowEnable"] as? Bool) ?? true
    // 自定义气泡：Widget 截图替换整个 callout
    if let calloutImage = qsImage(from: infoWindow?["content"]) {
      view.canShowCallout = infoWindowEnabled
      let imageView = UIImageView(image: calloutImage)
      // 官方初始化器为 initWithCustomView:（单数，自 SDK 5.0.0）
      view.customCalloutView = MACustomCalloutView(customView: imageView)
    } else {
      view.canShowCallout =
        infoWindowEnabled && !(infoWindow?.isEmpty ?? false)
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

  public func mapView(_ mapView: MAMapView, didSelect view: MAAnnotationView) {
    if let marker = view.annotation as? QsMarker {
      // 程序化选中（InfoWindow.show）不回发 markerTap，避免误报用户点击
      if programmaticSelection.remove(marker.customId) != nil { return }
      notifyDart("markerTap", marker.customId)
    }
  }

  public func mapView(
    _ mapView: MAMapView,
    annotationView view: MAAnnotationView,
    didChangeDragState newState: MAAnnotationViewDragState,
    fromOldState oldState: MAAnnotationViewDragState
  ) {
    guard newState == .ending, let marker = view.annotation as? QsMarker else { return }
    notifyDart(
      "markerDragEnd",
      [
        "id": marker.customId,
        "position": [marker.coordinate.latitude, marker.coordinate.longitude],
      ])
  }

  // ---- 覆盖物渲染器 ----

  public func mapView(_ mapView: MAMapView, rendererFor overlay: MAOverlay) -> MAOverlayRenderer? {
    switch overlay {
    case let polyline as QsPolyline:
      let renderer = MAPolylineRenderer(polyline: polyline)
      renderer.lineWidth = (polyline.json["width"] as? CGFloat) ?? 10
      let stroke = color(
        polyline.json["color"], fallback: UIColor(red: 0, green: 0, blue: 1, alpha: 0.8))
      // Dart 侧独立的 alpha 字段与颜色 ARGB 相乘
      let alpha = (polyline.json["alpha"] as? Double) ?? 1
      renderer.strokeColor =
        alpha >= 1 ? stroke : stroke.withAlphaComponent(CGFloat(alpha) * stroke.cgColor.alpha)
      // 虚线：MALineDashType 只有 none / square / dot
      // （无 .dash；dash/dashDot → square，dot → dot，capType/joinType 为 Android 专属）
      switch polyline.json["dashLineType"] as? String {
      case "dash", "dashDot": renderer.lineDashType = .square
      case "dot": renderer.lineDashType = .dot
      default: renderer.lineDashType = .none
      }
      return renderer
    case let polygon as QsPolygon:
      let renderer = MAPolygonRenderer(polygon: polygon)
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
      let renderer = MACircleRenderer(circle: circle)
      renderer.lineWidth = (circle.json["strokeWidth"] as? CGFloat) ?? 10
      renderer.strokeColor = color(
        circle.json["strokeColor"], fallback: UIColor.black.withAlphaComponent(0.8))
      renderer.fillColor = color(circle.json["fillColor"], fallback: UIColor.clear)
      return renderer
    default:
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

/// 从 icon JSON 构建 UIImage（带缓存）。
///
/// `defaultMarker` / `defaultMarkerWithHue` 返回 nil，由调用方回退到
/// SDK 自带大头针（iOS 无 Android 色相着色等价 API）；
/// `asset` / `assetImage` 支持带分辨率目录前缀的路径。
func qsImage(from json: Any?) -> UIImage? {
  guard let map = json as? [String: Any] else { return nil }
  switch map["type"] as? String {
  case "asset", "assetImage":
    guard var asset = map["asset"] as? String else { return nil }
    // 去除分辨率目录前缀（如 "2.0x/"）
    if let range = asset.range(of: #"^\d+(\.\d+)?x/"#, options: .regularExpression) {
      asset = String(asset[range.upperBound...])
    }
    let key = "asset:\(asset)" as NSString
    if let cached = qsImageCache.object(forKey: key) { return cached }
    let lookupKey = FlutterDartProject.lookupKey(forAsset: asset)
    guard let path = Bundle.main.path(forResource: lookupKey, ofType: nil),
      let image = UIImage(contentsOfFile: path)
    else { return nil }
    qsImageCache.setObject(image, forKey: key)
    return image
  case "bytes":
    guard let bytes = map["bytes"] as? FlutterStandardTypedData else { return nil }
    let key = qsBytesKey(bytes.data)
    if let cached = qsImageCache.object(forKey: key) { return cached }
    guard let image = UIImage(data: bytes.data) else { return nil }
    qsImageCache.setObject(image, forKey: key)
    return image
  default:
    // defaultMarker / defaultMarkerWithHue / 未知类型 → SDK 默认大头针
    return nil
  }
}
