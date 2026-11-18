[Simplified Chinese changelog](CHANGELOG_CN.md)

## 0.2.5

### Changed

- **Decoupled from the Material library**: core Dart sources now import
  `flutter/widgets.dart` instead of `flutter/material.dart`, so apps that do
  not use Material can depend on the plugin without pulling in the Material
  theme. No API changes.

### Documentation

- README and CHANGELOG are now English-first, with Simplified Chinese copies
  (`README_CN.md` / `CHANGELOG_CN.md`) linked from the top.

## 0.2.4

### Fixed

- **Android: overlays added before `mapLoaded` were not displayed.** The AMap SDK silently discards overlay calls such as `addMarker` / `addPolygon` before the map engine is initialized, while the plugin fires `onMapCreated` as soon as the PlatformView is constructed — earlier than engine readiness. Calls made "immediately inside `onMapCreated`" or "as initial overlays through `AMapWidget` constructor parameters" both fell into this window: the map rendered normally but markers / polygons / polylines / circles did not appear. Overlay calls (the four diff-update methods, `showInfoWindow` / `hideInfoWindow`, and initial overlays in creationParams) are now buffered until `mapLoaded` and replayed in order once the engine is ready; the post-`mapLoaded` path is unchanged. iOS is unaffected (MAMapView has no such timing constraint). Internally the buffering logic was extracted into a standalone `OverlayCallBuffer` with unit tests; a diagnostic log is emitted when buffering occurs, and unknown overlay methods now produce a `Log.w` warning instead of being silently ignored.

## 0.2.3

### Fixed

- **iOS marker anchor now only applies to custom icons.** Previously `centerOffset = size * (0.5 - anchor)` was also applied to the SDK's built-in pin (`MAPinAnnotationView`); since the pin tip already points at the coordinate, adding the -height/2 shift made the pin float above the location (confirmed on a real device). The anchor conversion is now applied only when a custom icon is used (`image` is non-null), restoring the correct position for default pins.

## 0.2.2

### Fixed

- **Android map lifecycle is now truly tied to the Activity.** The plugin implements `ActivityAware` + `DefaultLifecycleObserver`, so `MAMapView`'s `onResume` / `onPause` no longer means "resumed forever after creation" but follows the host Activity lifecycle. The map stops rendering when the app goes to the background (lower GPU / battery cost) and resumes automatically in the foreground; Activity recreation (rotation / split screen / dark-mode switch) and multi-map-instance scenarios now stay in sync. On `dispose`, `onPause` is only called while still resumed, avoiding a second `onPause` on an already paused map.
- **`map#dispose` message delivery fix.** The fallback `map#dispose` sent when an `AMapWidget` was disposed always used the `map#<mapId>` channel; under iOS hybrid composition that channel differs from the platform-view channel, so the message was silently dropped. It now goes through `_iosViewChannel ?? _mapIdChannel`, so the iOS disposal path delivers the message for real (Android behavior unchanged).

### Example and tests

- The marker stress-test page now reports three separate timings: Dart generation / Flutter submission / native processing confirmation (using `getCameraPosition` as the native barrier); the button is disabled until the controller is ready.
- Integration tests were rewritten: instead of launching the full example app, they now perform a minimal map creation plus native camera-control assertions, with the key supplied through `demo_config.dart`.

## 0.2.1

### Documentation

- Removed assertions about the maintenance status of the official `amap_flutter_map`. The README and pubspec description now use a neutral, self-focused positioning (single-package architecture / API compatibility, easy migration).

## 0.2.0

### Changed

- **Android rendering architecture upgraded from `MapView` (SurfaceView) to `TextureMapView` (TextureView) with TLHC composition.** The old SurfaceView content bypassed the view composition pipeline, so Flutter could only use Hybrid Composition (offscreen rendering, an extra GPU copy). With TextureView the Dart side moves to Flutter 3+'s default TLHC mode (`initExpensiveAndroidView` -> `initAndroidView`):
  - scrolling / animation stays in sync with the Flutter tree and page transitions are smoother;
  - layering and clipping of Flutter widgets over the map behave more naturally;
  - GC / memory structure is improved (TextureView double buffering adds roughly 20–40 MB of GPU memory);
  - the route-transition freeze mechanism (`map#freeze`) is retained and compatible with the new rendering path.
- No API changes; Dart code needs no modification to upgrade. A real-device regression pass is recommended (focus on `takeSnapshot`, custom info windows and page transitions).

## 0.1.5

### Added

- **`AMapWidget.zoomControlsEnabled`**: controls the visibility of the Android map's bottom-right +/- zoom buttons (default true, matching the SDK default). iOS's `MAMapView` has no built-in zoom buttons, so the flag is ignored on iOS.

## 0.1.4

### Fixed

- **iOS `InfoWindow.show: true` did not pop up the info window.** The deferred selection for `addMarker` called `selectAnnotation` synchronously inside `didAddAnnotationViews`, when the view had just been added and layout was not finished (especially visible on iOS 26); the SDK silently ignored the selection and `pendingShowSelection` had already been consumed and was never retried — the bubble did not appear and a leftover `programmaticSelection` swallowed the user's next real tap. Fix: deferred selection now moves asynchronously to the next frame and verifies the result, re-queuing if it is still ignored; at `mapLoaded` (first base-map frame ready), pending items whose view exists but was never successfully selected are retried. Android is unaffected (`showInfoWindow()` runs synchronously after `addMarker`, with state attached to the marker and independent of map initialization timing).

## 0.1.3

### Fixed

- **Android release builds with R8 (minify) no longer fail.** The combined AMap SDK is distributed on mavenCentral as plain JARs and cannot ship consumer ProGuard rules, so R8 reported "Missing class" for the optional GNSS module (`com.amap.ams.gnss.*`). The plugin now ships `consumerProguardFiles` (`dontwarn` + `keep com.amap.**` / `com.autonavi.**`); users no longer need to configure any ProGuard rules themselves.
- The example now keeps R8 enabled permanently as a regression check.

## 0.1.2

### Documentation

- Added a "Swift Package Manager" section to the iOS README chapter: why SwiftPM is not supported yet (`AMap3DMap` is only distributed via the CocoaPods trunk) and the CocoaPods fallback behavior and impact when SwiftPM integration is enabled.

## 0.1.1

### Documentation

- Added Podfile requirements to the iOS README chapter: AMap `AMap3DMap` is a static framework, so a host Podfile containing `use_frameworks!` (which newer Flutter templates may enable by default) makes `pod install` fail with a hard-to-diagnose error. Remove that line and ensure `platform :ios, '13.0'`; if frameworks are genuinely required, use `use_frameworks! :linkage => :static`.
- Added a "Permissions" section to the README: Android / iOS permission matrix (map display / my-location layer), Android Manifest declarations and runtime grants (with a `permission_handler` example), and iOS `Info.plist` purpose strings.

## 0.1.0

First published release. Single-package architecture (Dart layer + Android Kotlin + iOS Swift), API shape aligned with the official `amap_flutter_map` 3.0.0 for a smooth migration.

### Map and initialization

- `AMapInitializer.init`: one-step injection of the API key and sync of the privacy-compliance state on the Dart side (Android `MapsInitializer`, iOS `AMapServices` / `MAMapView` compliance APIs).
- `AMapWidget` map rendering (Android Hybrid Composition, iOS UiKitView).
- **Map language switching**: `AMapWidget.language` (Chinese/English, at creation and dynamically) plus `AMapController.setLanguage()`. SDK limitation: English only applies to standard map types and is mutually exclusive with custom styles.
- Camera control: `moveCamera` / `animateCamera` plus 10 `CameraUpdate` factories (`newLatLng` / `newLatLngZoom` / `newLatLngBounds` / `newCameraPosition` / `zoomTo` / `zoomBy` / `zoomIn` / `zoomOut` / `zoomByFocus` / `scrollBy`); `zoomByFocus` is emulated via projection math on Android and mapped to the native `zoomBy(_:focus:)` on iOS.
- Camera limits: `MinMaxZoomPreference` / `CameraTargetBounds` / `limitBounds`, all configurable at creation and dynamically.
- Gesture switches (zoom / pan / rotate / tilt) and UI switches (traffic / POI / buildings / labels / compass / scale bar), all updated through `didUpdateWidget`.
- My-location layer (`MyLocationStyleOptions`, five modes) and custom map styles (local `styleData` binaries + cloud style IDs).
- Full map event set: tap / long press / POI / marker tap and drag / info window tap / camera move (`onCameraMove` / `onCameraMoveEnd`) / map loaded (`onMapLoaded`).
- Map screenshot `takeSnapshot`, visible-region query `getVisibleRegion` and content approval number query (standard / satellite).

### Overlays

- **Diff-update engine**: `MarkerUpdates` / `PolylineUpdates` / `PolygonUpdates` / `CircleUpdates` diffs; `didUpdateWidget` sends only added / removed / changed items.
- Full `BitmapDescriptor` factory set (`defaultMarkerWithHue` / `fromIconPath` / `fromAssetImage` / `fromBytes`); textured polylines (`customTexture`), geodesic curves (`geodesic`) and dashed-line styles; polygons with holes (`holes`).
- **Custom info windows**: `InfoWindow.content` (image replaces the whole bubble) plus `renderWidgetToPng` (any Flutter widget -> PNG) and `controller.showInfoWindow` / `hideInfoWindow`.
- **Geometry utilities `GeometryUtil`** (built on clipper2): `xorCircles` / `xorPolygons` / `xorCirclePolygon` compute exclusive-OR regions and return ready-to-render polygons, holes included.
- Distance measurement: `AMapUtil.distanceBetween` / `distanceToBounds`.

### Fixes and cleanups

- **Fixed the iOS blue screen on map creation (root cause confirmed).** `limitBounds(null)` used to set `limitMapRect` to a zero rectangle (its semantics are a visible-region rectangle; zero means clamped to the world origin with forced zoom fitting) — the result was an all-ocean screen. The limit is now only set for a non-zero rectangle and restored to the full-world rectangle when cleared (verified on real devices with both 10.1.600 and 11.3.100).
- Android info-window tap-to-dismiss now matches iOS native deselect behavior: tapping empty map space actively closes the current bubble, with all show/hide entry points keeping the state in sync.
- Corrected the unit semantics of `scrollBy` / `zoomByFocus` on both platforms to Flutter logical pixels (the old implementation scrolled / focused by only about 1/3 of the requested distance on 3x devices).
- Both platforms now guarantee exactly one reply for `takeSnapshot` / camera callbacks (no dangling Futures after map disposal).
- iOS code review cleanups: unconditional reset of visual properties on recycled `viewFor` views (removing leftovers), stale-selection cleanup, degenerate-rectangle guard for `newLatLngBounds`, initial-camera reapply guard and replacement of all deprecated `UIScreen.main` usages.
- Android code review cleanups: three `updateMarker` fixes (`show=false` closes the bubble, partial updates no longer delete the bubble bitmap), fail-fast on a missing `mapId`, O(1) reverse lookup and handler-leak protection.
- iOS: fail-fast with a clear diagnostic when `MAMapView(frame:)` returns nil (commonly due to failed privacy compliance or a missing key), replacing the hard-to-locate KVO-bridge SIGABRT.

### Distribution and example

- Both platforms' SDKs are distributed through official channels and the plugin package ships no binaries: Android via mavenCentral `com.amap.api:3dmap-location-search:11.3.100_loc11.3.101_sea9.8.1`, iOS via the CocoaPods trunk `AMap3DMap ~> 11.2`.
- The example was restructured into a multi-page demo (map configuration / overlay management / camera control / geometry utilities / event logs / my-location layer / screenshot and approval number / custom info windows / custom map styles); keys are injected with `--dart-define`, and the repository contains no real credentials.
