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
      // 孔洞环（命名需 macOS 构建验证）
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
    // 地图类型（原生枚举值：1 normal / 2 satellite / 3 night / 4 navi / 5 bus）
    if let typeCode = params["mapType"] as? Int {
      mapView.mapType = MAMapType(rawValue: typeCode) ?? .standard
    }

    // 缩放范围
    if let minZoom = params["minZoom"] as? Double {
      mapView.setMinZoomLevel(minZoom, maxZoomLevel: nil)
    }
    if let maxZoom = params["maxZoom"] as? Double {
      mapView.setMinZoomLevel(nil, maxZoomLevel: maxZoom)
    }

    // 定位蓝点
    mapView.showsUserLocation = (params["myLocationEnabled"] as? Bool) ?? false
    // TODO(MVP): myLocationStyle（MAUserLocationRepresentation）与 customStyle 的 iOS 对接

    // 手势开关（US-04；属性名需 macOS 构建验证）
    applyGestures(params["gestures"])

    // UI 开关（路况/POI 点击/建筑物/标注/指南针/比例尺）
    applyUiOptions(params["uiOptions"])

    // 初始相机
    if let camera = params["initialCameraPosition"] as? [String: Any] {
      applyCameraPosition(camera)
    }

    // 覆盖物初始渲染
    (params["markers"] as? [[String: Any]])?.forEach(addMarker)
    (params["polylines"] as? [[String: Any]])?.forEach(addPolyline)
    (params["polygons"] as? [[String: Any]])?.forEach(addPolygon)
    (params["circles"] as? [[String: Any]])?.forEach(addCircle)

    bindMapEvents()
  }

  /// 手势开关（创建时与动态更新共用）。
  private func applyGestures(_ json: Any?) {
    guard let gestures = json as? [String: Bool] else { return }
    if let zoom = gestures["zoom"] { mapView.isZoomEnabled = zoom }
    if let scroll = gestures["scroll"] { mapView.isScrollEnabled = scroll }
    if let rotate = gestures["rotate"] { mapView.isRotateEnabled = rotate }
    // TODO(MVP): 倾斜手势 iOS 属性名待验证
  }

  /// UI 开关类选项（对齐官方 MAMapView 属性名，需 macOS 构建验证）。
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

  private func applyCameraPosition(_ json: [String: Any]) {
    guard let target = jsonToLatLng(json["target"]) else { return }
    let zoom = (json["zoom"] as? Double) ?? 10
    let tilt = (json["tilt"] as? Double) ?? 0
    let bearing = (json["bearing"] as? Double) ?? 0
    mapView.setCamera(
      MACameraPosition(
        target: target, zoom: zoom, tiltDegree: tilt, rotationDegree: bearing),
      animated: false)
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
      // 兼容两种 payload：纯 update（旧版）/ {update, animated, durationMs}
      let args = call.arguments as? [String: Any]
      guard let update = cameraUpdate(fromPayload: args?["update"] ?? call.arguments)
      else {
        result(FlutterError(code: "BAD_ARGS", message: "invalid camera update", details: nil))
        return
      }
      let animated = (args?["animated"] as? Bool) ?? false
      mapView.setCamera(update, animated: animated)
      result(nil)

    case "map#animateCamera":
      let args = (call.arguments as? [String: Any]) ?? [:]
      guard let update = cameraUpdate(fromPayload: args["update"]) else {
        result(FlutterError(code: "BAD_ARGS", message: "invalid camera update", details: nil))
        return
      }
      mapView.setCamera(update, animated: true)
      result(nil)

    case "map#getCameraPosition":
      let camera = mapView.camera
      result(camera?.toJsonMap() ?? nil)

    case "map#getVisibleRegion":
      let region = mapView.visibleRegion
      result([region.southwest.toJsonList(), region.northeast.toJsonList()])

    case "map#getContentApprovalNumber":
      // iOS：审图号在地图上自动显示（AMapLogo/审图号 label），无需查询
      result(nil)

    case "map#getSatelliteApprovalNumber":
      result(nil)

    case "map#setMapType":
      if let typeCode = call.arguments as? Int {
        mapView.mapType = MAMapType(rawValue: typeCode) ?? .standard
      }
      result(nil)

    case "map#setMinMaxZoomPreference":
      let json = call.arguments as? [String: Any] ?? [:]
      if let min = json["min"] as? Double {
        mapView.setMinZoomLevel(min, maxZoomLevel: json["max"] as? Double)
      }
      if let max = json["max"] as? Double {
        mapView.setMinZoomLevel(json["min"] as? Double, maxZoomLevel: max)
      }
      result(nil)

    case "map#setLimitBounds":
      // TODO(MVP): MAMapView 无直接 LatLngBounds 限制 API，no-op
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

  private func cameraUpdate(fromPayload payload: Any?) -> MACameraUpdate? {
    guard let json = payload as? [String: Any] else { return nil }
    switch json["op"] as? String {
    case "newLatLng":
      jsonToLatLng(json["latLng"]).map { MACameraUpdate.setTarget($0) }
    case "newLatLngZoom":
      guard let target = jsonToLatLng(json["latLng"]),
        let zoom = json["zoom"] as? Double
      else { return nil }
      return MACameraUpdate.setTargetZoom(target, zoom)
    case "newLatLngBounds":
      guard let bounds = jsonToLatLngBounds(json["bounds"]) else { return nil }
      return MACameraUpdate.fitBounds(bounds, withEdgeInsets: .zero)
    case "newCameraPosition":
      guard let pos = json["cameraPosition"] as? [String: Any],
        let target = jsonToLatLng(pos["target"])
      else { return nil }
      return MACameraUpdate.setCameraPosition(
        MACameraPosition(
          target: target,
          zoom: (pos["zoom"] as? Double) ?? 10,
          tiltDegree: (pos["tilt"] as? Double) ?? 0,
          rotationDegree: (pos["bearing"] as? Double) ?? 0))
    case "zoomTo":
      guard let zoom = json["zoom"] as? Double else { return nil }
      return MACameraUpdate.setZoomZoom(  // zoomTo
        mapView.camera?.zoom ?? 10, toZoom: zoom)
    case "zoomIn", "zoomOut":
      // iOS SDK 无独立 zoomIn/zoomOut，等价 zoomBy(±1)
      let amount: Double = (json["op"] as? String) == "zoomIn" ? 1 : -1
      return MACameraUpdate.zoomBy(
        amount, focus: CGPoint(x: mapView.bounds.midX, y: mapView.bounds.midY))
    case "zoomBy":
      guard let amount = json["amount"] as? Double else { return nil }
      return MACameraUpdate.zoomBy(
        amount, focus: CGPoint(x: mapView.bounds.midX, y: mapView.bounds.midY))
    case "zoomByFocus":
      guard let amount = json["amount"] as? Double,
        let focus = json["focus"] as? [Any],
        let fx = focus.first as? Double,
        let fy = focus.last as? Double
      else { return nil }
      return MACameraUpdate.zoomBy(amount, focus: CGPoint(x: fx, y: fy))
    case "scrollBy":
      let dx = (json["dx"] as? Double) ?? 0
      let dy = (json["dy"] as? Double) ?? 0
      return MACameraUpdate.scrollByScreenPoint(
        CGPoint(x: dx, y: dy))
    default:
      return nil
    }
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

  private func jsonToLatLngBounds(_ json: Any?) -> MABoundingRect? {
    guard let list = json as? [Any], list.count >= 2,
      let sw = jsonToLatLng(list[0]), let ne = jsonToLatLng(list[1])
    else { return nil }
    return MABoundingRect(
      southWest: sw, northEast: ne)
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
    if let camera = mapView.camera {
      notifyDart("cameraMoveEnd", camera.toJsonMap())
    }
  }

  public func mapView(_ mapView: MAMapView, regionWillChangeAnimated animated: Bool) {
    if let camera = mapView.camera {
      notifyDart("cameraMove", camera.toJsonMap())
    }
  }

  public func mapView(_ mapView: MAMapView, didTapMap coordinate: CLLocationCoordinate2D) {
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
    let view: MAAnnotationView
    if let reused = mapView.dequeueReusableAnnotationView(withIdentifier: marker.customId) {
      view = reused
    } else if image != nil {
      view = MAAnnotationView(annotation: marker, reuseIdentifier: marker.customId)
    } else {
      // 无自定义图标时使用 SDK 自带大头针
      view = MAPinAnnotationView(annotation: marker, reuseIdentifier: marker.customId)
    }
    view.annotation = marker
    view.image = image
    let infoWindow = marker.json["infoWindow"] as? [String: Any]
    // infoWindowEnable=false 时禁用气泡（对齐 Android 行为）
    let infoWindowEnabled = (marker.json["infoWindowEnable"] as? Bool) ?? true
    // 自定义气泡：Widget 截图替换整个 callout（命名需 macOS 构建验证）
    if let calloutImage = qsImage(from: infoWindow?["content"]) {
      view.canShowCallout = infoWindowEnabled
      let imageView = UIImageView(image: calloutImage)
      view.customCalloutView = MACustomCalloutView(customViews: [imageView])
    } else {
      view.canShowCallout =
        infoWindowEnabled && !(infoWindow?.isEmpty ?? false)
    }
    view.isDraggable = (marker.json["draggable"] as? Bool) ?? false
    view.isHidden = !((marker.json["visible"] as? Bool) ?? true)

    // 锚点：Dart 约定 (0,0) 左上 (1,1) 右下；iOS 用 centerOffset 换算
    let anchor = marker.json["anchor"] as? [Double]
    let u = (anchor?.count ?? 0) > 0 ? anchor![0] : 0.5
    let v = (anchor?.count ?? 0) > 1 ? anchor![1] : 1.0
    let width = image?.size.width ?? view.frame.width
    let height = image?.size.height ?? view.frame.height
    view.centerOffset = CGPoint(x: (u - 0.5) * width, y: (v - 0.5) * height)
    // TODO(MVP): alpha / rotation / zIndex 的 iOS 对应（MAAnnotationView 无直接属性，后续版本支持）
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
      renderer.strokeColor = color(
        polyline.json["color"], fallback: UIColor(red: 0, green: 0, blue: 1, alpha: 0.8))
      // 虚线：仅区分 none / dash（capType / joinType 为 Android 专属属性，iOS 用 SDK 默认值）
      renderer.lineDashType =
        (polyline.json["dashLineType"] as? String) == "dash" ? .dash : .none
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

extension MACameraPosition {
  func toJsonMap() -> [String: Any?] {
    [
      "target": [target.latitude, target.longitude],
      "zoom": zoom,
      "tilt": tiltDegree,
      "bearing": rotationDegree,
    ]
  }
}

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
