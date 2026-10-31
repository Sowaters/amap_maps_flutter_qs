library;

import 'dart:ui';

import 'dart:typed_data';

import 'package:flutter/painting.dart' show AssetImage, ImageConfiguration;
import 'package:flutter/services.dart' show AssetBundle;

import '../model/latlng.dart';
import '../util/line_smoothing.dart';
import 'overlay_enums.dart';

part 'marker.dart';
part 'polyline.dart';
part 'polygon.dart';
part 'circle.dart';
part 'overlay_updates.dart';

/// 全局覆盖物 id 自增计数器。
///
/// 对齐官方 `amap_flutter_map` 的 `BaseOverlay`：构造覆盖物时不传 id
/// 即自动生成（官方用 hashCode 字符串，这里用更稳定的递增计数）。
/// [Marker.copyWith] 等会自动沿用原 id，差量更新不受影响。
int _nextOverlayId = 0;

/// 所有地图覆盖物的密封基类。
///
/// Dart 3 密封类：`switch` 表达式可对 [Marker]、[Polyline]、[Polygon]、
/// [Circle] 做穷尽匹配，新增覆盖物类型时编译器强制处理所有分支。
///
/// 对齐官方形状：构造时 [id] 可省略，省略时自动生成唯一 id；
/// 同一地图上 id 相同的覆盖物会被差量更新机制视为「同一个对象」。
sealed class MapObject {
  /// 覆盖物唯一标识。
  final String id;

  /// 是否可见。
  final bool visible;

  /// Z 轴层级（越大越靠上）。
  final double zIndex;

  MapObject({String? id, this.visible = true, this.zIndex = 0.0})
    : id = id ?? 'overlay_${_nextOverlayId++}';

  /// 序列化（用于平台通道传输）。
  Map<String, Object?> toJson();
}

/// Marker 的气泡。
class InfoWindow {
  /// 标题。
  final String? title;

  /// 副文本。
  final String? snippet;

  /// 自定义气泡内容（图片）。
  ///
  /// 非空时原生端忽略 [title] / [snippet]，用该图片替换整个气泡窗口；
  /// 典型用法是用 [renderWidgetToPng] 把 Flutter Widget 渲染成图片后传入
  /// `BitmapDescriptor.fromBytes(...)`。图片为静态快照，内容交互不支持；
  /// 内容变化时需重新生成图片并更新 Marker。
  final BitmapDescriptor? content;

  /// 是否在 Marker 添加/更新时自动显示气泡（无需点击）。
  ///
  /// 注意：原生「删旧建新」式差量更新会重建气泡，因此 [show] 为 true 时
  /// 每次该 Marker 更新后气泡都会保持弹出状态。
  final bool show;

  /// 点击气泡回调。
  ///
  /// 对自定义图片气泡而言，点击气泡任意位置都会触发此回调；
  /// 图片中的按钮或其他控件不支持独立交互。
  final void Function(String markerId)? onTap;

  const InfoWindow({
    this.title,
    this.snippet,
    this.content,
    this.show = false,
    this.onTap,
  });

  /// 空气泡（隐藏）。
  static const InfoWindow noText = InfoWindow();

  /// 复制并替换指定字段（参数名对齐官方 `Param` 后缀约定）。
  InfoWindow copyWith({
    String? titleParam,
    String? snippetParam,
    BitmapDescriptor? contentParam,
    bool? showParam,
    void Function(String markerId)? onTapParam,
  }) => InfoWindow(
    title: titleParam ?? title,
    snippet: snippetParam ?? snippet,
    content: contentParam ?? content,
    show: showParam ?? show,
    onTap: onTapParam ?? onTap,
  );

  /// 序列化（回调不传输，由原生事件回调后分发）。
  Map<String, Object?> toJson() => <String, Object?>{
    'title': title,
    'snippet': snippet,
    'content': content?.toJson(),
    'show': show,
  };
}

/// Marker 图标描述。
///
/// 工厂方法与常量命名对齐官方 `amap_flutter_map` 的 `BitmapDescriptor`：
/// [defaultMarker] / [defaultMarkerWithHue] / [fromIconPath] /
/// [fromAssetImage] / [fromBytes]。
class BitmapDescriptor {
  final _BitmapType _type;
  final String? _asset;

  /// 资源图像的缩放（fromAssetImage 解析出的 scale）。
  final double? _scale;

  /// 内存图片字节（PNG）。
  final Uint8List? _bytes;

  /// 色相角度 [0, 360)（defaultMarkerWithHue）。
  final double? _hue;

  const BitmapDescriptor._(
    this._type,
    this._asset,
    this._scale,
    this._bytes,
    this._hue,
  );

  /// 红色。
  static const double hueRed = 0.0;

  /// 橙色.
  static const double hueOrange = 30.0;

  /// 黄色.
  static const double hueYellow = 60.0;

  /// 绿色.
  static const double hueGreen = 120.0;

  /// 青色.
  static const double hueCyan = 180.0;

  /// 天蓝色.
  static const double hueAzure = 210.0;

  /// 蓝色.
  static const double hueBlue = 240.0;

  /// 紫色.
  static const double hueViolet = 270.0;

  /// 酒红色.
  static const double hueMagenta = 300.0;

  /// 玫瑰红.
  static const double hueRose = 330.0;

  /// SDK 默认图标。
  static const BitmapDescriptor defaultMarker = BitmapDescriptor._(
    _BitmapType.defaultMarker,
    null,
    null,
    null,
    null,
  );

  /// 旧版默认图标别名（保留兼容，建议改用 [defaultMarker]）。
  @Deprecated('Use defaultMarker instead')
  static const BitmapDescriptor defaultIcon = defaultMarker;

  /// 带色相角度的默认着色图标（0.0 ~ 360.0，见 [hueRed] 等常量）。
  static BitmapDescriptor defaultMarkerWithHue(double hue) {
    assert(0.0 <= hue && hue < 360.0);
    return BitmapDescriptor._(
      _BitmapType.defaultMarkerWithHue,
      null,
      null,
      null,
      hue,
    );
  }

  /// 按资源路径创建图标（最常用的自定义图标方式）。
  ///
  /// 路径为 Flutter asset 路径，如 `assets/location_marker.png`；
  /// 使用插件自带资源时需带包前缀
  /// （如 `packages/amap_maps_flutter_qs/res/marker.png`）。
  static BitmapDescriptor fromIconPath(String iconPath) =>
      BitmapDescriptor._(_BitmapType.asset, iconPath, null, null, null);

  /// 从资源图像创建（会根据 [ImageConfiguration] 做分辨率感知解析）。
  ///
  /// 对齐官方同名 API。
  static Future<BitmapDescriptor> fromAssetImage(
    ImageConfiguration configuration,
    String assetName, {
    AssetBundle? bundle,
    String? package,
    bool mipmaps = true,
  }) async {
    final assetImage = AssetImage(assetName, package: package, bundle: bundle);
    final key = await assetImage.obtainKey(configuration);
    return BitmapDescriptor._(
      _BitmapType.assetImage,
      key.name,
      key.scale,
      null,
      null,
    );
  }

  /// 从内存 PNG 字节创建（配合 `renderWidgetToPng` 渲染 Widget 快照）。
  static BitmapDescriptor fromBytes(Uint8List bytes) =>
      BitmapDescriptor._(_BitmapType.bytes, null, null, bytes, null);

  /// 旧版资源图标别名（保留兼容，建议改用 [fromIconPath]）。
  @Deprecated('Use fromIconPath instead')
  static BitmapDescriptor fromAsset(String asset) => fromIconPath(asset);

  /// 序列化。
  Map<String, Object?> toJson() => <String, Object?>{
    'type': _type.name,
    'asset': _asset,
    'scale': _scale,
    'bytes': _bytes,
    'hue': _hue,
  };

  /// 值相等：相同类型 + 相同参数即相等。
  ///
  /// 关键场景是 `fromBytes` / `fromIconPath`：用户每次 `setState` 重建
  /// 图标描述时（尤其 `fromBytes`），若无值相等，差量 diff 会把整批
  /// Marker 误判为「已变更」并全量下发原生（原生端随之反复解码位图）。
  /// 相同实例走 `identical` 短路，不同实例按内容比较。
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BitmapDescriptor &&
          other._type == _type &&
          other._asset == _asset &&
          other._scale == _scale &&
          other._hue == _hue &&
          _listEquals(other._bytes, _bytes);

  /// O(1) 哈希：不参与 bytes 内容哈希（大图标逐字节哈希会让 2000 级
  /// Marker 集合的每次 diff 都变成 O(n × bytes)，得不偿失）。
  ///
  /// bytes 内容不同但其余字段相同的实例哈希相同 —— 只损失哈希桶分布，
  /// 与 [==] 保持一致性约束（相等必同哈希）。Marker 的 `==` 先比较 id /
  /// position 等廉价字段，哈希碰撞不会引发位图逐字节比较。
  @override
  int get hashCode => Object.hash(_type, _asset, _scale, _hue);

  static bool _listEquals(Uint8List? a, Uint8List? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

enum _BitmapType {
  defaultMarker,
  defaultMarkerWithHue,
  asset,
  assetImage,
  bytes,
}
