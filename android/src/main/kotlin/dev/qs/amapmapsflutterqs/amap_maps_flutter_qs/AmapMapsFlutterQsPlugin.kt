package dev.qs.amapmapsflutterqs.amap_maps_flutter_qs

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.StandardMessageCodec

/// 插件入口：注册主通道（init / 隐私合规）与地图 PlatformView。
class AmapMapsFlutterQsPlugin :
    FlutterPlugin,
    MethodCallHandler {

    companion object {
        const val VIEW_TYPE = "amap_maps_flutter_qs/map"
        const val MAIN_CHANNEL = "amap_maps_flutter_qs"

        // mapId -> 地图实例（跨方法调用路由用）
        private val mapViews = LinkedHashMap<Int, AMapPlatformView>()

        fun registerView(mapId: Int, view: AMapPlatformView) {
            mapViews[mapId] = view
        }

        fun unregisterView(mapId: Int) {
            mapViews.remove(mapId)
        }
    }

    private lateinit var context: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        val channel = MethodChannel(binding.binaryMessenger, MAIN_CHANNEL)
        channel.setMethodCallHandler(this)
        binding.platformViewRegistry.registerViewFactory(
            VIEW_TYPE,
            AMapPlatformViewFactory(binding.binaryMessenger, StandardMessageCodec.INSTANCE),
        )
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "init" -> {
                val args = call.arguments as? Map<*, *> ?: run {
                    result.error("BAD_ARGS", "init expects a map", null)
                    return
                }
                val apiKey = args["apiKey"] as? Map<*, *>
                val privacy = args["privacy"] as? Map<*, *>
                initialize(apiKey, privacy)
                result.success(null)
            }
            "updatePrivacyShow" -> {
                val privacy = call.arguments as? Map<*, *>
                applyPrivacyShow(
                    privacy?.get("hasShow") as? Boolean ?: false,
                    privacy?.get("hasContains") as? Boolean ?: false,
                )
                result.success(null)
            }
            "updatePrivacyAgree" -> {
                val privacy = call.arguments as? Map<*, *>
                applyPrivacyAgree(privacy?.get("hasAgree") as? Boolean ?: false)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun initialize(apiKey: Map<*, *>?, privacy: Map<*, *>?) {
        // Android Key：Dart 侧传入时程序化注入；也可走 Manifest meta-data。
        val androidKey = apiKey?.get("androidKey") as? String
        if (!androidKey.isNullOrBlank()) {
            com.amap.api.maps.MapsInitializer.setApiKey(androidKey)
        }
        // 隐私合规：必须在任何 MapView 创建前调用。
        val hasShow = privacy?.get("hasShow") as? Boolean ?: false
        val hasContains = privacy?.get("hasContains") as? Boolean ?: false
        val hasAgree = privacy?.get("hasAgree") as? Boolean ?: false
        com.amap.api.maps.MapsInitializer.updatePrivacyShow(context, hasShow, hasContains)
        com.amap.api.maps.MapsInitializer.updatePrivacyAgree(context, hasAgree)
    }

    private fun applyPrivacyShow(hasShow: Boolean, hasContains: Boolean) {
        com.amap.api.maps.MapsInitializer.updatePrivacyShow(context, hasShow, hasContains)
    }

    private fun applyPrivacyAgree(hasAgree: Boolean) {
        com.amap.api.maps.MapsInitializer.updatePrivacyAgree(context, hasAgree)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        mapViews.clear()
    }
}
