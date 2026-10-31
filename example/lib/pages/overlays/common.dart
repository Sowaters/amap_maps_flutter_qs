import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:amap_maps_flutter_qs/amap_maps_flutter_qs.dart';

/// 覆盖物 demo 通用组件：事件日志卡片、分组控制面板、页面骨架、
/// 运行时图标绘制工具。

/// 悬浮在地图底部的事件日志卡片。
class OverlayEventLog extends StatelessWidget {
  final String text;

  const OverlayEventLog(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 8,
      right: 8,
      bottom: 8,
      child: Card(
        color: Theme.of(context).colorScheme.inversePrimary,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(text, style: const TextStyle(fontSize: 12)),
        ),
      ),
    );
  }
}

/// 面板上的一个操作按钮。
class OverlayAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const OverlayAction(this.icon, this.label, this.onTap);
}

/// 一组操作按钮（带分组标题）。
class OverlayActionGroup {
  final String label;
  final List<OverlayAction> actions;

  const OverlayActionGroup(this.label, this.actions);
}

/// 覆盖物 demo 通用页面骨架：地图 + 悬浮事件日志 + 底部分组控制面板。
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
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [map, OverlayEventLog(event)],
            ),
          ),
          SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final group in groups) ...[
                    _GroupChips(group: group),
                    const SizedBox(height: 6),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupChips extends StatelessWidget {
  final OverlayActionGroup group;

  const _GroupChips({required this.group});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Text(
            group.label,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final action in group.actions)
              ActionChip(
                avatar: Icon(action.icon, size: 18),
                label: Text(action.label, style: const TextStyle(fontSize: 12)),
                onPressed: action.onTap,
              ),
          ],
        ),
      ],
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
