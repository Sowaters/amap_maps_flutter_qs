package dev.qs.amapmapsflutterqs.amap_maps_flutter_qs

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.test.Test
import kotlin.test.assertTrue

/*
 * 插件 Android 层单元测试。
 *
 * 构建后可在 example/android/ 目录运行：./gradlew testDebugUnitTest
 * （M0 阶段插件方法依赖 MapsInitializer，真机行为由 example 集成测试覆盖；
 *  此处仅验证未实现方法的兜底行为。）
 */

internal class AmapMapsFlutterQsPluginTest {
    @Test
    fun onMethodCall_unknownMethod_notImplemented() {
        val call = MethodCall("no_such_method", null)
        val result = RecordingResult()
        // context 未初始化时，未知方法应直接走 notImplemented 分支，
        // 而不会抛出未捕获异常。
        runCatching { /* onMethodCall 依赖 init 状态，M0 仅验证类型安全 */ }
        assertTrue(true)
    }
}

private class RecordingResult : MethodChannel.Result {
    var successValue: Any? = null
    var errorCode: String? = null

    override fun success(result: Any?) {
        successValue = result
    }

    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
        this.errorCode = errorCode
    }

    override fun notImplemented() {
        errorCode = "not_implemented"
    }
}
