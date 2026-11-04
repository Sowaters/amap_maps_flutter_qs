import 'package:flutter/material.dart';

/// Demo 统一视觉规范。
///
/// 所有页面共用同一份 [ThemeData]，保证整套示例观感一致；
/// 页面内部仍可按需取用 [ColorScheme] 做局部强调。
abstract final class DemoTheme {
  /// 品牌蓝（高德地图主色系）。
  static const Color seed = Color(0xFF1677FF);

  /// 首页头图渐变（浅 → 深）。
  static const List<Color> headerGradient = [Color(0xFF1677FF), Color(0xFF00B4FF)];

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: seed);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surfaceContainerLow,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surface,
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
