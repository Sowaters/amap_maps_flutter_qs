import 'package:flutter/foundation.dart';

/// 插件日志工具。
///
/// debug 模式默认开启，日志前缀 `[AMapQS]`，可在 Xcode / Android Studio
/// 控制台直接过滤。release 模式默认关闭。
///
/// 排查「地图只显示但其他功能不生效」时，按时间顺序关注以下日志：
/// - `[AMapQS] init ...`：ApiKey / 隐私合规是否正常下发到原生
/// - `[AMapQS] map#<id> platform view created`：原生视图是否创建成功
/// - `[AMapQS] map#<id> -> map#updateMarkers ...`：Dart 是否下发了覆盖物更新
/// - `[AMapQS] native -> map#<id> cameraMoveEnd`：原生事件是否回传
/// - 原生端（Xcode 控制台）`[AMapQS]` 前缀的 guard 失败日志，能直接定位
///   覆盖物被丢弃的原因（id 缺失 / 图标解码失败 / 坐标点不足等）。
abstract final class AMapLogger {
  /// 日志总开关，可在运行时动态调整。
  static bool enabled = kDebugMode;

  /// 输出一条调试日志。
  static void d(String message) {
    if (enabled) {
      debugPrint('[AMapQS] $message');
    }
  }

  /// 输出一条警告日志（无论开关是否关闭都会输出，便于暴露问题）。
  static void w(String message) {
    debugPrint('[AMapQS][警告] $message');
  }
}
