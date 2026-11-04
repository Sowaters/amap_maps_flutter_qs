# 高德「3D 地图 / 定位 / 搜索」合包 SDK（com.amap.api:3dmap-location-search）
# 在 mavenCentral 上以纯 JAR 形式分发，无法自带 consumer proguard 规则；
# 本文件经插件的 consumerProguardFiles 随 AAR 传递给使用者，
# 使用者开启 release minify（R8）时无需再自行配置 proguard 规则。
#
# 1) dontwarn：SDK 引用了可选 GNSS 模块类（如 com.amap.ams.gnss.GnssSoftLocator），
#    合包依赖中不含该模块，缺省时自动降级，不影响功能
-dontwarn com.amap.**
-dontwarn com.autonavi.**
#
# 2) keep：SDK 内部大量使用反射与 JNI（按类名/方法名查找），
#    混淆或裁剪会导致运行时 NoSuchMethod / JNI 链接失败
-keep class com.amap.** { *; }
-keep class com.autonavi.** { *; }
