import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// 将任意 Flutter Widget 渲染为 PNG 字节。
///
/// 典型用途：自定义 Marker 气泡 —— 把 Widget 截图后传入
/// `BitmapDescriptor.fromBytes(...)`，再赋给 `InfoWindow.content`。
///
/// 实现方式：把 [widget] 挂载到应用 Overlay 的屏幕外区域，等待一帧
/// 渲染完成后通过 [RenderRepaintBoundary.toImage] 截图。
///
/// 注意：结果为静态快照，气泡内容不支持实时刷新与内部交互；
/// 内容变化时需重新调用此方法并更新 Marker。
Future<Uint8List> renderWidgetToPng(
  BuildContext context,
  Widget widget, {
  double maxWidth = 240,
  double? maxHeight,
  double pixelRatio = 3.0,
}) async {
  final overlay = Overlay.of(context, rootOverlay: true);
  final key = GlobalKey();
  final entry = OverlayEntry(
    builder: (_) => Positioned(
      // 屏幕外渲染，用户不可见
      left: -20000,
      top: -20000,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: maxHeight ?? double.infinity,
        ),
        child: RepaintBoundary(key: key, child: widget),
      ),
    ),
  );
  overlay.insert(entry);
  try {
    await WidgetsBinding.instance.endOfFrame;
    // 首帧可能仅完成布局未完成绘制，再等一帧兜底
    if (key.currentContext == null) {
      await WidgetsBinding.instance.endOfFrame;
    }
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      throw StateError('renderWidgetToPng: RepaintBoundary not attached');
    }
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw StateError('renderWidgetToPng: toByteData failed');
    }
    return byteData.buffer.asUint8List();
  } finally {
    entry.remove();
  }
}
