import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:amap_maps_flutter_qs/amap_maps_flutter_qs.dart';

import '../../ui/demo_widgets.dart';

/// 覆盖物 demo 通用组件：基于全局 Demo UI 体系的页面骨架，
/// 事件日志、分组控制面板直接复用 [DemoEventLog] / [DemoChipGroup]。

/// 悬浮在地图底部的事件日志卡片（[DemoEventLog] 的覆盖物页别名）。
typedef OverlayEventLog = DemoEventLog;

/// 面板上的一个操作按钮（[DemoChip] 的覆盖物页别名）。
typedef OverlayAction = DemoChip;

/// 一组操作按钮（带分组标题）。
class OverlayActionGroup {
  final String label;
  final List<OverlayAction> actions;

  const OverlayActionGroup(this.label, this.actions);
}

/// 覆盖物 demo 通用页面骨架：地图 + 悬浮事件日志 + 底部圆角控制面板。
///
/// [map] 由各页面自行构造（覆盖物集合与回调都留在页面 State 里），
/// 骨架只负责布局，保证所有子页面观感一致。
class OverlayDemoScaffold extends StatelessWidget {
  final String title;
  final AMapWidget map;
  final String event;
  final List<OverlayActionGroup> groups;

  const OverlayDemoScaffold({
    super.key,
    required this.title,
    required this.map,
    required this.event,
    required this.groups,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [map, OverlayEventLog(event)],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLowest,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              border: Border(top: BorderSide(color: scheme.outlineVariant)),
            ),
            child: SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.42,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 32,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: scheme.outlineVariant,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      for (final group in groups) ...[
                        DemoChipGroup(
                          label: group.label,
                          chips: group.actions,
                        ),
                        const SizedBox(height: 6),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 运行时用 dart:ui 绘制一个实心圆点图标，转 PNG 字节。
///
/// 演示 [BitmapDescriptor.fromBytes] 的典型用法。
Future<BitmapDescriptor> renderDotIcon(Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const center = Offset(36, 36);
  canvas.drawCircle(center, 24, Paint()..color = Colors.white);
  canvas.drawCircle(center, 19, Paint()..color = color);
  final image = await recorder.endRecording().toImage(72, 72);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
}
