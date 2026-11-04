import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'package:amap_maps_flutter_qs/amap_maps_flutter_qs.dart';

import '../demo_config.dart';

/// 自定义地图样式（CustomStyleOptions）。
///
/// 两种模式（二选一，本地二进制优先），支持创建参数与运行时动态切换：
/// 1. 云端样式 ID：在高德开放平台「自定义地图」控制台创建，填入下方输入框；
/// 2. 本地样式数据：下载样式压缩包后把 `style.data` / `style_extra.data`
///    放入 `assets/styles/`，用「加载本地样式」按钮读取。
///
/// 切换经 `controller.setCustomStyle` 动态下发（map#setCustomStyle），
/// 无需重建地图实例；Android / iOS 均已实现。
class CustomStylePage extends StatefulWidget {
  const CustomStylePage({super.key});

  @override
  State<CustomStylePage> createState() => _CustomStylePageState();
}

class _CustomStylePageState extends State<CustomStylePage> {
  AMapController? _controller;
  final _styleIdController = TextEditingController();
  bool _enabled = false;
  bool _loadingLocal = false;
  Uint8List? _styleData;
  Uint8List? _styleExtraData;
  String _status = '填入样式 ID 或加载本地样式后打开开关';

  @override
  void dispose() {
    _styleIdController.dispose();
    super.dispose();
  }

  /// 当前生效的样式选项：本地二进制优先（对齐 SDK 约定），其次云端 ID。
  CustomStyleOptions? get _currentOptions {
    if (!_enabled) return null;
    if (_styleData != null) {
      return CustomStyleOptions(
        true,
        styleData: _styleData,
        styleExtraData: _styleExtraData,
      );
    }
    final styleId = _styleIdController.text.trim();
    if (styleId.isEmpty) return null;
    return CustomStyleOptions(true, customStyleId: styleId);
  }

  /// 动态下发：样式开关 / 内容变化时经通道更新，无需重建地图
  Future<void> _applyStyle() async {
    final options = _currentOptions;
    setState(() {
      _status = options == null
          ? '自定义样式已关闭'
          : _styleData != null
          ? '已下发本地样式数据（style.data ${_styleData!.length} 字节）'
          : '已下发云端样式 ID：${options.customStyleId}';
    });
    await _controller?.setCustomStyle(options);
  }

  /// 从 assets/styles/ 读取本地样式数据（官方控制台下载的压缩包内容）。
  Future<void> _loadLocalStyle() async {
    if (_loadingLocal) return;
    setState(() => _loadingLocal = true);
    try {
      final main = await rootBundle.load('assets/styles/style.data');
      Uint8List? extra;
      try {
        extra = (await rootBundle.load('assets/styles/style_extra.data'))
            .buffer
            .asUint8List();
      } catch (_) {
        // style_extra.data 可选
      }
      if (!mounted) return;
      setState(() {
        _styleData = main.buffer.asUint8List();
        _styleExtraData = extra;
        _enabled = true;
        _status = '本地样式加载成功（style.data ${_styleData!.length} 字节'
            '${extra != null ? '，style_extra.data ${extra.length} 字节' : '，无扩展数据'}）';
      });
      await _applyStyle();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _status = '未找到 assets/styles/style.data——请把控制台下载的样式包'
            '解压后放入该目录（见目录内 README）';
      });
    } finally {
      if (mounted) setState(() => _loadingLocal = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final styleId = _styleIdController.text.trim();
    final hasLocal = _styleData != null;

    return Scaffold(
      appBar: AppBar(title: const Text('自定义地图样式')),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                AMapWidget(
                  // 初始样式走创建参数；后续切换全走 controller.setCustomStyle
                  // 动态下发，不再重建地图实例
                  initialCameraPosition: initialCamera,
                  customStyleOptions: _currentOptions,
                  onMapCreated: (controller) {
                    _controller = controller;
                  },
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
                        hasLocal
                            ? '模式：本地样式数据\n$_status'
                            : styleId.isNotEmpty
                            ? '模式：云端样式 ID：$styleId\n$_status'
                            : _status,
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
                    enabled: !hasLocal,
                    decoration: InputDecoration(
                      labelText: '云端样式 ID',
                      hintText: '在开放平台「自定义地图」控制台创建',
                      isDense: true,
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.style, size: 20),
                      // 本地模式优先：禁用输入框提示当前模式
                      helperText: hasLocal ? '已加载本地样式，云端 ID 模式停用' : null,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _loadingLocal ? null : _loadLocalStyle,
                        icon: _loadingLocal
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.folder_open, size: 16),
                        label: const Text('加载本地样式', style: TextStyle(fontSize: 13)),
                      ),
                      // 动态开关：经 controller.setCustomStyle 下发，不重建地图
                      // （SwitchListTile 需有界宽度，须包 Expanded）
                      Expanded(
                        child: SwitchListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.only(left: 8),
                          title: const Text(
                            '启用自定义样式（动态下发）',
                            style: TextStyle(fontSize: 13),
                          ),
                          value: _enabled && _currentOptions != null,
                          onChanged: (v) {
                            setState(() => _enabled = v);
                            _applyStyle();
                          },
                        ),
                      ),
                    ],
                  ),
                  const Text(
                    '提示：切换经 map#setCustomStyle 动态下发（Android / iOS 已实现）；'
                    '启用自定义样式后审图号查询返回空（SDK 约定）。',
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
