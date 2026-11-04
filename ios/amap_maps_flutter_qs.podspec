#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint amap_maps_flutter_qs.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'amap_maps_flutter_qs'
  s.version          = '0.1.0'
  s.summary          = 'AMap (Gaode) 3D map plugin for Flutter.'
  s.description      = <<-DESC
A modern, maintained AMap 3D map plugin for Flutter.
Successor of the abandoned amap_flutter_map.
                       DESC
  s.homepage         = 'https://github.com/Sowaters/amap_maps_flutter_qs'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Sowaters' => 'Sowaters@users.noreply.github.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'amap_maps_flutter_qs/Sources/amap_maps_flutter_qs/**/*'
  s.dependency 'Flutter'
  # 对齐 11.x 版本线；trunk 最高 11.2.100（蓝屏根因在插件侧已修复，SDK 版本无碍）
  s.dependency 'AMap3DMap', '~> 11.2'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # 高德 SDK 隐私清单（如需要可在此配置 resource_bundles）
  # s.resource_bundles = {'amap_maps_flutter_qs_privacy' => ['amap_maps_flutter_qs/Sources/amap_maps_flutter_qs/PrivacyInfo.xcprivacy']}
end
