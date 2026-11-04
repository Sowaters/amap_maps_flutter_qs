#
# 本地 vendored podspec：绕过 CocoaPods trunk 上的 AMap3DMap 11.2.000，
# 使用官方 SDK 包内的 11.3.100 framework（构建于 2026-09-21，晚于 iOS 26 发布）。
#
# 背景：iOS 26 真机上 11.2.000 蓝屏 —— 探针证实 SDK 逻辑层（坐标换算/地图状态）
# 自洽地按 4× 世界（2^28 Mercator 空间）计算，但渲染/瓦片管线仍按旧 2^26 世界
# 取瓦片，可见区域被钳制到世界左上角（85.05N, -180W）→ 整屏海面。
# 11.3.100 疑似包含修复（官方 changelog 页面尚未收录该版本）。
#
# 上次接入失败的链接错误（Undefined symbol: _GLKMatrix4Identity / GLKView）
# 根因：官方 Demo 工程显式链接 GLKit.framework，本 podspec 已补 GLKit + OpenGLES。
#
# 验证通过后：若 11.3.100 上架 CocoaPods，删除本文件与 AMapSDK/ 目录，
# 恢复 Podfile 中 `pod 'AMap3DMap'` 远端依赖；并更新插件 podspec 版本约束。
#
Pod::Spec.new do |s|
  s.name             = 'AMap3DMap'
  s.version          = '11.3.100'
  s.summary          = 'AMap 3D Map SDK 11.3.100 (vendored from official SDK package)'
  s.description      = <<-DESC
Local vendored copy of MAMapKit 11.3.100 + AMapFoundationKit from the
official AMap iOS SDK package, used to fix the iOS 26 world-corner
(blue screen) rendering issue of 11.2.000.
                       DESC
  s.homepage         = 'https://lbs.amap.com'
  s.license          = { :type => 'Copyright', :text => 'Copyright (c) AutoNavi/AMap. All rights reserved.' }
  s.author           = { 'AMap' => 'https://lbs.amap.com' }
  s.source           = { :path => '.' }
  s.platform         = :ios, '13.0'

  # 同时 vendor 地图主框架与基础库（对应远端 AMap3DMap + AMapFoundation 两个 pod）
  s.vendored_frameworks = 'AMapSDK/MAMapKit.framework', 'AMapSDK/AMapFoundationKit.framework'

  # 关键：AMap.bundle 必须拷贝进 App 资源目录（与官方 trunk podspec 一致）。
  # Flutter debug 构建启用 debug-dylib（Xcode 16+）后 bundleForClass 返回主 bundle，
  # SDK 的 MAResources mapBundlePath 从主 bundle 找 AMap.bundle；缺失即崩溃：
  # 'NSInvalidArgumentException' -[NSBundle initWithURL:]: nil URL argument
  s.resources = 'AMapSDK/MAMapKit.framework/AMap.bundle'

  # GLKit/OpenGLES：官方 Demo 显式链接 GLKit（11.x 渲染层引用 GLKView/GLKMatrix）；
  # 系统库缺失即报 Undefined symbol: _GLKMatrix4Identity / _OBJC_CLASS_$_GLKView
  s.frameworks = 'CoreLocation', 'SystemConfiguration', 'CoreTelephony', 'Security',
                 'JavaScriptCore', 'GLKit', 'OpenGLES'
  s.libraries  = 'z', 'c++', 'sqlite3'
  s.xcconfig   = { 'OTHER_LDFLAGS' => '-ObjC' }

  # 供应商 framework 已含 arm64 真机 slice；与插件一致地排除 i386 模拟器
  s.pod_target_xcconfig = { 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
end
