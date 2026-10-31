part of 'overlay.dart';

/// 覆盖物差量更新结果。
///
/// 对齐基线插件与 `google_maps_flutter` 的 `*Updates` 设计：
/// [AMapWidget] 在 `didUpdateWidget` 时对新旧集合做 diff，
/// 仅将增 / 删 / 改三部分下发原生，避免全量重建原生对象
/// （PRD §4.1 关键决策，US-03 性能验收项）。
///
/// 判定规则（以 [MarkerUpdates] 为例，其余类型一致）：
/// - id 只在旧集合 → 删除
/// - id 只在新集合 → 新增
/// - id 两边都有但 `==` 不同（回调除外）→ 更新
class _MapObjectDiff<T extends MapObject> {
  final Set<T> toAdd;
  final Set<T> toUpdate;
  final Set<T> toRemove;

  const _MapObjectDiff(this.toAdd, this.toUpdate, this.toRemove);
}

_MapObjectDiff<T> _diffObjects<T extends MapObject>(
  Set<T> previous,
  Set<T> current,
) {
  final oldById = <String, T>{for (final o in previous) o.id: o};
  final newIds = <String>{for (final o in current) o.id};

  final toAdd = <T>{};
  final toUpdate = <T>{};
  final toRemove = <T>{};

  for (final object in current) {
    final old = oldById[object.id];
    if (old == null) {
      toAdd.add(object);
    } else if (old != object) {
      toUpdate.add(object);
    }
  }
  for (final object in previous) {
    if (!newIds.contains(object.id)) toRemove.add(object);
  }
  return _MapObjectDiff(toAdd, toUpdate, toRemove);
}

/// 通道差量更新 payload 的公共形状。
///
/// `toAdd` / `toUpdate` 为覆盖物 JSON 数组，`toRemove` 为 id 数组。
mixin class _OverlayUpdatesPayload {
  Map<String, Object?> _payload(
    Iterable<MapObject> toAdd,
    Iterable<MapObject> toUpdate,
    Iterable<MapObject> toRemove,
  ) => <String, Object?>{
    'toAdd': toAdd.map((o) => o.toJson()).toList(),
    'toUpdate': toUpdate.map((o) => o.toJson()).toList(),
    'toRemove': toRemove.map((o) => o.id).toList(),
  };
}

/// [Marker] 集合的差量更新结果。
class MarkerUpdates with _OverlayUpdatesPayload {
  final Set<Marker> markersToAdd;
  final Set<Marker> markersToChange;
  final Set<Marker> markersToRemove;

  const MarkerUpdates._(this.markersToAdd, this.markersToChange, this.markersToRemove);

  factory MarkerUpdates.from(Set<Marker> previous, Set<Marker> current) {
    final diff = _diffObjects(previous, current);
    return MarkerUpdates._(diff.toAdd, diff.toUpdate, diff.toRemove);
  }

  /// 通道序列化（方法名 `map#updateMarkers`）。
  Map<String, Object?> toJson() =>
      _payload(markersToAdd, markersToChange, markersToRemove);

  /// 三部分均为空时为 true（无需下发）。
  bool get isEmpty =>
      markersToAdd.isEmpty && markersToChange.isEmpty && markersToRemove.isEmpty;
}

/// [Polyline] 集合的差量更新结果。
class PolylineUpdates with _OverlayUpdatesPayload {
  final Set<Polyline> polylinesToAdd;
  final Set<Polyline> polylinesToChange;
  final Set<Polyline> polylinesToRemove;

  const PolylineUpdates._(this.polylinesToAdd, this.polylinesToChange, this.polylinesToRemove);

  factory PolylineUpdates.from(Set<Polyline> previous, Set<Polyline> current) {
    final diff = _diffObjects(previous, current);
    return PolylineUpdates._(diff.toAdd, diff.toUpdate, diff.toRemove);
  }

  /// 通道序列化（方法名 `map#updatePolylines`）。
  Map<String, Object?> toJson() =>
      _payload(polylinesToAdd, polylinesToChange, polylinesToRemove);

  /// 三部分均为空时为 true（无需下发）。
  bool get isEmpty =>
      polylinesToAdd.isEmpty && polylinesToChange.isEmpty && polylinesToRemove.isEmpty;
}

/// [Polygon] 集合的差量更新结果。
class PolygonUpdates with _OverlayUpdatesPayload {
  final Set<Polygon> polygonsToAdd;
  final Set<Polygon> polygonsToChange;
  final Set<Polygon> polygonsToRemove;

  const PolygonUpdates._(this.polygonsToAdd, this.polygonsToChange, this.polygonsToRemove);

  factory PolygonUpdates.from(Set<Polygon> previous, Set<Polygon> current) {
    final diff = _diffObjects(previous, current);
    return PolygonUpdates._(diff.toAdd, diff.toUpdate, diff.toRemove);
  }

  /// 通道序列化（方法名 `map#updatePolygons`）。
  Map<String, Object?> toJson() =>
      _payload(polygonsToAdd, polygonsToChange, polygonsToRemove);

  /// 三部分均为空时为 true（无需下发）。
  bool get isEmpty =>
      polygonsToAdd.isEmpty && polygonsToChange.isEmpty && polygonsToRemove.isEmpty;
}

/// [Circle] 集合的差量更新结果（基线插件缺失，本插件补齐）。
class CircleUpdates with _OverlayUpdatesPayload {
  final Set<Circle> circlesToAdd;
  final Set<Circle> circlesToChange;
  final Set<Circle> circlesToRemove;

  const CircleUpdates._(this.circlesToAdd, this.circlesToChange, this.circlesToRemove);

  factory CircleUpdates.from(Set<Circle> previous, Set<Circle> current) {
    final diff = _diffObjects(previous, current);
    return CircleUpdates._(diff.toAdd, diff.toUpdate, diff.toRemove);
  }

  /// 通道序列化（方法名 `map#updateCircles`）。
  Map<String, Object?> toJson() =>
      _payload(circlesToAdd, circlesToChange, circlesToRemove);

  /// 三部分均为空时为 true（无需下发）。
  bool get isEmpty =>
      circlesToAdd.isEmpty && circlesToChange.isEmpty && circlesToRemove.isEmpty;
}
