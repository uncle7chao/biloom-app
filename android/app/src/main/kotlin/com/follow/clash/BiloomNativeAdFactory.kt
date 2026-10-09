package com.follow.clash

import android.graphics.Color
import android.graphics.Typeface
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import com.google.android.gms.ads.nativead.MediaView
import com.google.android.gms.ads.nativead.NativeAd
import com.google.android.gms.ads.nativead.NativeAdView
import io.flutter.plugins.googlemobileads.NativeAdFactory

/**
 * BiLoom 原生广告工厂（v4）：为 Flutter 侧 [NativeAd]（factoryId =
 * "biloomNative"）构建平台视图。单行图文布局：图标 + 标题 + 媒体位，
 * 固定高度与 Flutter 侧 _kNativeCardHeight（72dp）对齐。
 *
 * 政策要求：NativeAdView 必须登记可点击资源（headline/icon/mediaView），
 * 并通过 setNativeAd 绑定广告对象 —— 缺一会被 AdMob 判违规。
 */
class BiloomNativeAdFactory(
    private val context: android.content.Context,
) : NativeAdFactory {

    override fun createNativeAd(
        nativeAd: NativeAd,
        options: Map<String, Any>?,
    ): NativeAdView {
        val density = context.resources.displayMetrics.density
        fun dp(v: Int) = (v * density).toInt()

        val adView = NativeAdView(context)

        val root = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setBackgroundColor(Color.WHITE)
            setPadding(dp(12), dp(8), dp(12), dp(8))
        }

        // 图标（可缺省，缺了隐藏）
        val iconView = ImageView(context).apply {
            layoutParams = LinearLayout.LayoutParams(dp(40), dp(40)).apply {
                marginEnd = dp(10)
            }
            scaleType = ImageView.ScaleType.FIT_CENTER
        }
        nativeAd.icon?.drawable?.let { iconView.setImageDrawable(it) }

        // 标题 + 文本列
        val textColumn = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                0,
                LinearLayout.LayoutParams.WRAP_CONTENT,
                1f,
            )
        }
        val headlineView = TextView(context).apply {
            text = nativeAd.headline
            setTextColor(Color.DKGRAY)
            setTypeface(typeface, Typeface.BOLD)
            textSize = 14f
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
        }
        val bodyView = TextView(context).apply {
            text = nativeAd.body
            setTextColor(Color.GRAY)
            textSize = 12f
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { topMargin = dp(2) }
        }
        textColumn.addView(headlineView)
        textColumn.addView(bodyView)

        // 媒体位（宽度占余量，视觉上是右侧小图区）
        val mediaView = MediaView(context).apply {
            layoutParams = LinearLayout.LayoutParams(dp(56), dp(56)).apply {
                marginStart = dp(10)
            }
            setImageScaleType(ImageView.ScaleType.CENTER_CROP)
        }

        root.addView(iconView)
        root.addView(textColumn)
        root.addView(mediaView)
        adView.addView(root)

        // 登记可点击资源（缺失的资源不登记，AdMob 自行判定）
        adView.headlineView = headlineView
        adView.bodyView = bodyView
        adView.iconView = iconView
        adView.mediaView = mediaView
        adView.setNativeAd(nativeAd)

        return adView
    }
}
