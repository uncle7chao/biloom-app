package com.follow.clash

import com.follow.clash.plugins.AppPlugin
import com.follow.clash.plugins.ServicePlugin
import com.follow.clash.plugins.TilePlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(AppPlugin())
        flutterEngine.plugins.add(ServicePlugin())
        flutterEngine.plugins.add(TilePlugin())
        ServiceState.attachFlutterEngine(flutterEngine)
        // v4 原生广告：注册 NativeAdFactory（factoryId 与 Flutter 侧
        // ads_native.dart 的 kNativeAdFactoryId 一致）。SDK 未初始化时
        // 注册也无害 —— google_mobile_ads 的注册只是存工厂，不触发网络。
        io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin
            .registerNativeAdFactory(flutterEngine, "biloomNative", BiloomNativeAdFactory(this))
    }

    override fun onDestroy() {
        flutterEngine?.let(ServiceState::detachFlutterEngine)
        super.onDestroy()
    }
}
