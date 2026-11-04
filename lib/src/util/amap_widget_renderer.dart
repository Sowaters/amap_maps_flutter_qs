import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Widget 快照结果：PNG 字节 + 渲染时的逻辑尺寸（points）。
///
/// [width] / [height] 应传给 `BitmapDescriptor.fromBytes` 的同名参数，
/// 原生端据此把位图还原到正确的逻辑尺寸（iOS 尤其需要：UIImage 默认把
/// PNG 物理像素当点显示，pixelRatio 3 渲染的快照会放大 3 倍）。
typedef QsWidgetSnapshot = ({Uint8List png, double width, double height});

/// 将任意 Flutter Widget 渲染为 PNG 快照。
///
/// 典型用途：自定义 Marker 气泡 —— 把 Widget 截图后传入
/// `BitmapDescriptor.fromBytes(..., width: 快照.width, height: 快照.height)`，
/// 再赋给 `InfoWindow.content`。
///
/// 实现方式：把 [widget] 挂载到应用 Overlay 的屏幕外区域，等待一帧
/// 渲染完成后通过 [RenderRepaintBoundary.toImage] 截图。
///
/// 注意：结果为静态快照，气泡内容不支持实时刷新与内部交互；
/// 内容变化时需重新调用此方法并更新 Marker。
Future<QsWidgetSnapshot> renderWidgetToPng(
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
    // 逻辑尺寸须在 toImage 之前取（boundary.size 即 points）
    final logicalSize = boundary.size;
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw StateError('renderWidgetToPng: toByteData failed');
    }
    return (
      png: byteData.buffer.asUint8List(),
      width: logicalSize.width,
      height: logicalSize.height,
    );
  } finally {
    entry.remove();
  }
}
