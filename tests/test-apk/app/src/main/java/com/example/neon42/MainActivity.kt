package com.example.neon42

import android.app.Activity
import android.os.Bundle
import android.view.View
import android.widget.TextView
import android.graphics.Color
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.webkit.WebViewClient
import android.webkit.WebSettings

class MainActivity : Activity() {

    companion object {
        const val EXTRA_LAUNCH_WEBVIEW = "launch_webview"
    }

    private lateinit var webView: WebView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val token = intent.getStringExtra(EXTRA_LAUNCH_WEBVIEW)
        if (token != null) {
            webView = WebView(this).apply {
                settings.javaScriptEnabled = true
                settings.domStorageEnabled = true
                settings.cacheMode = WebSettings.LOAD_NO_CACHE
                clearCache(true)

                webViewClient = WebViewClient()
                webChromeClient = WebChromeClient()

                loadUrl(token)
            }

            setContentView(webView)
        } else {
            val tv = TextView(this).apply {
                text = "42"
                textSize = 320f
                setTextColor(Color.RED)
                setBackgroundColor(Color.BLACK)
                textAlignment = View.TEXT_ALIGNMENT_CENTER
                setShadowLayer(40f, 0f, 0f, Color.RED)
            }

            window.decorView.systemUiVisibility =
                View.SYSTEM_UI_FLAG_FULLSCREEN or
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION

            setContentView(tv)
        }
    }
}
