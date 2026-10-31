import 'package:flutter/material.dart';

import 'package:amap_maps_flutter_qs/amap_maps_flutter_qs.dart';

import '../demo_config.dart';

/// 自定义地图样式（CustomStyleOptions）。
///
/// 两种模式（二选一，本地二进制优先）：
/// 1. 云端样式 ID：在高德开放平台「自定义地图」控制台创建，填入下方输入框；
/// 2. 本地样式数据：下载压缩包后把 `style.data` / `style_extra.data`
///    读成字节传入 `styleData` / `styleExtraData`。
///
/// 说明：样式随地图创建参数下发，切换时本页通过 ValueKey 重建地图实例
/// （与 myLocationStyleOptions 一致）；仅 Android 已实现，iOS 待对接。
class CustomStylePage extends StatefulWidget {
  const CustomStylePage({super.key});

  @override
  State<CustomStylePage> createState() => _CustomStylePageState();
}

class _CustomStylePageState extends State<CustomStylePage> {
  final _styleIdController = TextEditingController();
  bool _enabled = false;

  @override
  void dispose() {
    _styleIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final styleId = _styleIdController.text.trim();
    final hasStyle = styleId.isNotEmpty;
    final style = _enabled && hasStyle
        ? CustomStyleOptions(true, customStyleId: styleId)
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('自定义地图样式')),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                AMapWidget(
                  // 样式选项当前仅创建时下发：参数变化时重建地图实例
                  key: ValueKey('style-$_enabled-$styleId'),
                  initialCameraPosition: initialCamera,
                  customStyleOptions: style,
                ),
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 8,
                  child: Card(
                    color: Theme.of(context).colorScheme.inversePrimary,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        _enabled && hasStyle
                            ? '已启用云端样式：$styleId'
                            : '未启用（填入样式 ID 并打开开关）',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _styleIdController,
                    decoration: const InputDecoration(
                      labelText: '云端样式 ID',
                      hintText: '在开放平台「自定义地图」控制台创建',
                      isDense: true,
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.style, size: 20),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    dense: true,
                    title: const Text('启用自定义样式（切换时重建地图）', style: TextStyle(fontSize: 13)),
                    value: _enabled && hasStyle,
                    onChanged: hasStyle
                        ? (v) => setState(() => _enabled = v)
                        : null,
                  ),
                  const Text(
                    '提示：仅 Android 已实现；本地模式用 rootBundle 读 style.data '
                    '字节传 CustomStyleOptions(true, styleData: bytes)。',
                    style: TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
