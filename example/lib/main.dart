import 'package:flutter/material.dart';

import 'package:amap_maps_flutter_qs/amap_maps_flutter_qs.dart';

import 'demo_config.dart';
import 'pages/camera_page.dart';
import 'pages/convex_hull_page.dart';
import 'pages/custom_bubble_page.dart';
import 'pages/custom_style_page.dart';
import 'pages/events_page.dart';
import 'pages/geometry_page.dart';
import 'pages/map_types_page.dart';
import 'pages/marker_stress_page.dart';
import 'pages/my_location_page.dart';
import 'pages/overlays_page.dart';
import 'pages/snapshot_page.dart';
import 'ui/demo_theme.dart';
import 'ui/demo_widgets.dart';

export 'ui/demo_widgets.dart' show showDemoTip;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AMapInitializer.init(apiKey: demoApiKey, privacyStatement: demoPrivacy);
  runApp(const DemoApp());
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'amap_maps_flutter_qs demo',
      theme: DemoTheme.light(),
      home: const DemoHomePage(),
    );
  }
}

/// 一个 demo 入口。
class _DemoEntry {
  final IconData icon;
  final String title;
  final String description;
  final WidgetBuilder page;
  final List<String> tags;

  const _DemoEntry(
    this.icon,
    this.title,
    this.description,
    this.page, {
    this.tags = const [],
  });
}

/// 一组 demo 入口（首页分区）。
class _DemoSection {
  final IconData icon;
  final String title;
  final List<_DemoEntry> entries;

  const _DemoSection(this.icon, this.title, this.entries);
}

const _sections = <_DemoSection>[
  _DemoSection(Icons.layers_outlined, '地图基础', [
    _DemoEntry(
      Icons.map_outlined,
      '地图配置（动态更新）',
      'MapType / 手势 / 路况、建筑、标注、指南针、比例尺 / limitBounds 全部运行时切换',
      _buildMapTypes,
      tags: ['动态更新'],
    ),
    _DemoEntry(
      Icons.style,
      '自定义地图样式',
      'CustomStyleOptions 云端样式 ID 模式，运行时开关自定义样式',
      _buildCustomStyle,
      tags: ['Android'],
    ),
    _DemoEntry(
      Icons.my_location,
      '定位蓝点',
      'MyLocationStyleOptions：五种定位模式切换、精度圈颜色',
      _buildMyLocation,
    ),
  ]),
  _DemoSection(Icons.location_pin, '覆盖物', [
    _DemoEntry(
      Icons.category_outlined,
      '覆盖物管理',
      '细分 6 个子页：Marker 增删改与图标工厂、Marker 属性与气泡控制、'
          'Polyline（geodesic/纹理/虚线/平滑/箭头）、GPS 轨迹、Polygon（镂空/孔洞）、Circle',
      _buildOverlays,
      tags: ['6 个子页'],
    ),
    _DemoEntry(
      Icons.bubble_chart_outlined,
      '自定义气泡',
      'renderWidgetToPng 把 Flutter Widget 截图后赋给 InfoWindow.content',
      _buildCustomBubble,
      tags: ['Widget → PNG'],
    ),
    _DemoEntry(
      Icons.bolt,
      'Marker 压力测试',
      '200 / 500 / 1000 / 2000 个 Marker 全量替换的差量更新耗时与真机渲染',
      _buildMarkerStress,
      tags: ['性能'],
    ),
    _DemoEntry(
      Icons.fence,
      '凸包围栏 · 凸包计算',
      '点击地图用 fence.png 图标放点，Andrew 单调链实时计算凸包生成多边形；'
          '拖拽顶点重算；撤销按创建顺序 LIFO 回退',
      _buildConvexHull,
      tags: ['凸包'],
    ),
  ]),
  _DemoSection(Icons.control_camera, '相机与事件', [
    _DemoEntry(
      Icons.control_camera,
      '相机控制',
      'CameraUpdate 全部工厂（含 zoomByFocus）、moveCamera / animateCamera、实时相机状态',
      _buildCamera,
      tags: ['10 种工厂'],
    ),
    _DemoEntry(
      Icons.touch_app,
      '地图事件',
      '地图点击/长按、POI 点击、Marker 点击/拖拽、相机移动回调的事件日志 + 距离测量',
      _buildEvents,
    ),
  ]),
  _DemoSection(Icons.design_services, '工具与合规', [
    _DemoEntry(
      Icons.highlight_alt,
      '几何运算 · 不相交区域',
      'GeometryUtil XOR：两圆月牙形、两多边形 L 形、同心圆环形（含孔洞）',
      _buildGeometry,
      tags: ['XOR'],
    ),
    _DemoEntry(
      Icons.camera_alt_outlined,
      '截图与合规',
      'takeSnapshot 地图截图、审图号查询（上架合规展示）',
      _buildSnapshot,
      tags: ['审图号'],
    ),
  ]),
];

Widget _buildMapTypes(BuildContext context) => const MapTypesPage();
Widget _buildCustomStyle(BuildContext context) => const CustomStylePage();
Widget _buildMyLocation(BuildContext context) => const MyLocationPage();
Widget _buildOverlays(BuildContext context) => const OverlaysPage();
Widget _buildCustomBubble(BuildContext context) => const CustomBubblePage();
Widget _buildMarkerStress(BuildContext context) => const MarkerStressPage();
Widget _buildConvexHull(BuildContext context) => const ConvexHullPage();
Widget _buildCamera(BuildContext context) => const CameraPage();
Widget _buildEvents(BuildContext context) => const EventsPage();
Widget _buildGeometry(BuildContext context) => const GeometryPage();
Widget _buildSnapshot(BuildContext context) => const SnapshotPage();

int get _entryCount =>
    _sections.fold(0, (sum, section) => sum + section.entries.length);

/// 所有 (所属分区, 入口) 扁平序列，搜索用。
List<(_DemoSection, _DemoEntry)> get _allEntries => [
      for (final section in _sections)
        for (final entry in section.entries) (section, entry),
    ];

class DemoHomePage extends StatefulWidget {
  const DemoHomePage({super.key});

  @override
  State<DemoHomePage> createState() => _DemoHomePageState();
}

class _DemoHomePageState extends State<DemoHomePage> {
  String _query = '';

  List<(_DemoSection, _DemoEntry)> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return [
      for (final (section, entry) in _allEntries)
        if (entry.title.toLowerCase().contains(q) ||
            entry.description.toLowerCase().contains(q) ||
            entry.tags.any((tag) => tag.toLowerCase().contains(q)))
          (section, entry),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final searching = _query.trim().isNotEmpty;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: _HomeHeader()),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: SearchBar(
                  hintText: '搜索示例：相机 / Marker / 轨迹 / XOR…',
                  leading: const Icon(Icons.search),
                  trailing: [
                    if (searching)
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _query = ''),
                      ),
                  ],
                  elevation: const WidgetStatePropertyAll(0),
                  constraints: const BoxConstraints(minHeight: 44),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
            ),
            if (!searching)
              ..._buildSections(context)
            else
              _buildSearchResults(context),
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 24, 16, 0),
                child: Center(
                  child: Text(
                    '社区插件 · MIT License · API 以 README / MIGRATION 为准',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSections(BuildContext context) {
    return [
      for (final section in _sections) ...[
        SliverToBoxAdapter(
          child: DemoSectionHeader(section.title, icon: section.icon),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              mainAxisExtent: 152,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) =>
                  _buildCard(context, section.entries[index], null),
              childCount: section.entries.length,
            ),
          ),
        ),
      ],
    ];
  }

  Widget _buildSearchResults(BuildContext context) {
    final results = _filtered;
    if (results.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(child: Text('没有匹配的示例，换个关键词试试')),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final (section, entry) = results[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SizedBox(height: 152, child: _buildCard(context, entry, section.title)),
            );
          },
          childCount: results.length,
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context, _DemoEntry entry, String? sectionLabel) {
    return DemoEntryCard(
      icon: entry.icon,
      title: entry.title,
      description: entry.description,
      tags: sectionLabel == null ? entry.tags : [...entry.tags, sectionLabel],
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(builder: entry.page),
      ),
    );
  }
}

/// 首页头图：插件名 + 简介 + 徽标。
class _HomeHeader extends StatelessWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context) {
    const gradient = DemoTheme.headerGradient;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.map_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'amap_maps_flutter_qs',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '高德地图 Flutter 插件 · 功能示例',
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildBadge('v0.1.0'),
              _buildBadge('$_entryCount 个示例'),
              _buildBadge('iOS · Android'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11, color: Colors.white),
      ),
    );
  }
}
