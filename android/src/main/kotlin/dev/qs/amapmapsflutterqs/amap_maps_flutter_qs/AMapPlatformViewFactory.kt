package dev.qs.amapmapsflutterqs.amap_maps_flutter_qs

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/// 地图 PlatformView 工厂。creationParams 由 Dart 侧 AMapWidget 传入。
class AMapPlatformViewFactory(
    private val binaryMessenger: BinaryMessenger,
    private val messageCodec: MessageCodec<Any>,
) : PlatformViewFactory(messageCodec) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = args as? Map<*, *> ?: emptyMap<Any, Any>()
        return AMapPlatformView(context, binaryMessenger, params)
    }
}
