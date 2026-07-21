package kr.mysaver.android

import android.annotation.SuppressLint
import android.content.ActivityNotFoundException
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.util.Log
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import androidx.activity.OnBackPressedCallback
import androidx.appcompat.app.AppCompatActivity
import androidx.browser.customtabs.CustomTabsIntent
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat

class MainActivity : AppCompatActivity() {
    private lateinit var webView: WebView
    private var pendingSharedUrl: String? = null
    private var pendingOAuthJs: String? = null

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        webView = WebView(this).apply {
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.databaseEnabled = true
            settings.allowFileAccess = false
            settings.allowContentAccess = false
            settings.mediaPlaybackRequiresUserGesture = false
            settings.userAgentString = settings.userAgentString + " MySaverApp/1.0"

            webViewClient = MySaverWebViewClient(this@MainActivity)
            addJavascriptInterface(NativeBridge(this@MainActivity), "MySaverNative")
        }
        // WebView 에 직접 setPadding 을 걸면 시각적으로 잘 반영되지 않는 경우가 많아
        // FrameLayout 컨테이너로 감싸고 컨테이너에 inset padding 을 적용한다.
        // 컨테이너 배경은 status/navigation bar 영역에 노출되므로 frontend 와 동일한 흰색.
        val rootContainer = FrameLayout(this).apply {
            setBackgroundColor(Color.WHITE)
            addView(
                webView,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT,
                ),
            )
        }
        setContentView(rootContainer)

        // Status bar / navigation bar 아래로 WebView 컨텐츠를 밀어 넣음.
        // targetSdk 36 → Android 15+ 에선 edge-to-edge 가 강제되므로 inset 처리는 필수.
        ViewCompat.setOnApplyWindowInsetsListener(rootContainer) { v, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            v.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            insets
        }

        // 콜드 스타트: 인텐트가 OAuth callback 이면 처리 후 메인 페이지 로드.
        consumeOAuthCallback(intent)
        pendingSharedUrl = SharedStore.consumePendingShare(this)
            ?: intent.getStringExtra(EXTRA_SHARED_URL)
        webView.loadUrl(AppConfig.SITE_URL)

        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                if (webView.canGoBack()) {
                    webView.goBack()
                } else {
                    isEnabled = false
                    onBackPressedDispatcher.onBackPressed()
                }
            }
        })
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)

        if (consumeOAuthCallback(intent)) return

        val newShare = SharedStore.consumePendingShare(this)
            ?: intent.getStringExtra(EXTRA_SHARED_URL)
        if (newShare != null) dispatchSharedUrl(newShare)
    }

    fun onWebViewPageFinished() {
        pendingSharedUrl?.let {
            dispatchSharedUrl(it)
            pendingSharedUrl = null
        }
        pendingOAuthJs?.let {
            webView.evaluateJavascript(it, null)
            pendingOAuthJs = null
        }
    }

    private fun dispatchSharedUrl(url: String) {
        val safe = url.replace("\\", "\\\\").replace("'", "\\'")
        webView.evaluateJavascript(
            "window.dispatchEvent(new CustomEvent('mysaver:shared', { detail: { url: '$safe' } }));",
            null,
        )
    }

    // MARK: OAuth callback

    /** `mysaver://oauth?token=...&user=base64&isNewUser=1&hasHandle=0` 인텐트 처리. */
    private fun consumeOAuthCallback(intent: Intent?): Boolean {
        val data = intent?.data ?: return false
        if (data.scheme != AppConfig.URL_SCHEME || data.host != AppConfig.OAUTH_CALLBACK_HOST) return false

        val token = data.getQueryParameter("token") ?: return false
        val isNewUser = data.getQueryParameter("isNewUser") == "1"
        val hasHandle = data.getQueryParameter("hasHandle") == "1"
        val userBase64 = data.getQueryParameter("user").orEmpty()

        SharedStore.saveToken(this, token)

        val path = when {
            isNewUser && !hasHandle -> "/setup-handle"
            isNewUser -> "/welcome"
            else -> "/"
        }
        scheduleOAuthInjection(token, userBase64, path)

        // 인텐트의 data 가 동일하게 다시 처리되지 않도록 클리어.
        intent.data = null
        return true
    }

    private fun scheduleOAuthInjection(token: String, userBase64: String, path: String) {
        val tokenLit = jsEscape(token)
        val pathLit = jsEscape(path)
        // 프론트는 btoa(unescape(encodeURIComponent(json))) 로 인코딩 → 역순으로 UTF-8 안전 디코드.
        val userLit = if (userBase64.isEmpty()) {
            "null"
        } else {
            "JSON.parse(decodeURIComponent(escape(atob('${jsEscape(userBase64)}'))))"
        }

        val js = """
            (function() {
              try {
                localStorage.setItem('saveme_token', '$tokenLit');
                var u = $userLit;
                if (u) localStorage.setItem('saveme_user', JSON.stringify(u));
                window.location.href = '$pathLit';
              } catch (e) {}
            })();
        """.trimIndent()

        // 콜드 스타트(WebView 미로드)면 페이지 로드 완료 후 실행, 아니면 즉시 실행.
        if (this::webView.isInitialized && !webView.url.isNullOrEmpty()) {
            webView.evaluateJavascript(js, null)
        } else {
            pendingOAuthJs = js
        }
    }

    private fun jsEscape(s: String): String = s
        .replace("\\", "\\\\")
        .replace("'", "\\'")
        .replace("\n", "\\n")
        .replace("\r", "\\r")

    companion object {
        const val EXTRA_SHARED_URL = "shared_url"
    }

    /// Web → Native bridge. `window.MySaverNative.setToken(t)` / `clearToken()` / `openOAuth(provider)`.
    inner class NativeBridge(private val ctx: MainActivity) {
        @JavascriptInterface
        fun setToken(token: String) {
            SharedStore.saveToken(ctx, token)
        }

        @JavascriptInterface
        fun clearToken() {
            SharedStore.clearToken(ctx)
        }

        /**
         * 소셜 로그인 시 호출. WebView 내에서는 Google 이 거부하므로 Chrome Custom Tabs 로 위임.
         * 완료 후 `mysaver://oauth?...` URL 이 MainActivity 의 VIEW intent 로 돌아옴.
         */
        @JavascriptInterface
        fun openOAuth(provider: String) {
            val url = Uri.parse("${AppConfig.SITE_URL}/login")
                .buildUpon()
                .appendQueryParameter("platform", "android")
                .appendQueryParameter("autoOauth", provider)
                .build()

            ctx.runOnUiThread {
                val tabs = CustomTabsIntent.Builder()
                    .setShowTitle(true)
                    .build()
                tabs.launchUrl(ctx, url)
            }
        }
    }
}

class MySaverWebViewClient(private val activity: MainActivity) : WebViewClient() {
    override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
        val uri = request.url
        if (isInternal(uri)) return false

        val scheme = uri.scheme.orEmpty().lowercase()

        // intent:// 스킴: 카카오 OAuth 등이 WebView 에 던지는 외부 앱 호출 URL.
        // 일반 Intent.ACTION_VIEW 로 던지면 안 되고 Intent.parseUri 로 디코딩해야
        // package/action/extra 가 살아서 카카오톡 앱이 정상 실행된다.
        if (scheme == "intent") {
            return handleIntentScheme(view, request.url.toString())
        }

        // 카카오 로그인 우회: WebView 가 kakaolink/kakaokompassauth/kakaotalk 스킴을 처리하지 못해
        // 흰 화면이 되는 걸 방지. 명시적으로 외부 앱(KakaoTalk) 으로 위임한다.
        // (아래 generic fallback 도 동일 동작이지만 의도를 명시하고 디버그 로그를 분리.)
        if (scheme.startsWith("kakao")) {
            return launchExternal(view, uri, label = "kakao")
        }

        // http(s) 가 아닌 외부 스킴(market://, tel://, mailto:// 등)도
        // 명시적으로 startActivity 로 위임 — WebView 가 처리하려다 흰 화면 되는 걸 방지.
        return launchExternal(view, uri, label = scheme)
    }

    private fun launchExternal(view: WebView, uri: Uri, label: String): Boolean {
        return try {
            val intent = Intent(Intent.ACTION_VIEW, uri).apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK }
            view.context.startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            // 해당 스킴을 처리할 앱이 없음 → WebView 에 그냥 두기 (보통 에러 페이지)
            Log.w(TAG, "외부 앱 미설치 ($label): ${e.message}")
            false
        }
    }

    private fun handleIntentScheme(view: WebView, url: String): Boolean {
        val intent = try {
            Intent.parseUri(url, Intent.URI_INTENT_SCHEME)
        } catch (e: Exception) {
            Log.w(TAG, "intent:// parse 실패: ${e.message}")
            return false
        }

        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        // 보안: 한 번 더 명시적 selector 차단 — webview 가 직접 임의 selector intent 를 띄우지 못하게.
        intent.selector = null
        intent.addCategory(Intent.CATEGORY_BROWSABLE)
        intent.component = null

        // 1) 타겟 앱(예: com.kakao.talk) 실행 시도
        try {
            view.context.startActivity(intent)
            return true
        } catch (_: ActivityNotFoundException) {
            // 앱 미설치 → 아래 fallback
        }

        // 2) intent URL 에 명시된 fallback URL 로 webview 이동 (앱 없으면 웹으로 진행)
        val fallback = intent.getStringExtra("browser_fallback_url")
        if (!fallback.isNullOrEmpty()) {
            view.loadUrl(fallback)
            return true
        }

        // 3) 마지막 fallback: Play Store 로 보내기
        val pkg = intent.`package`
        if (!pkg.isNullOrEmpty()) {
            try {
                val market = Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$pkg"))
                    .apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK }
                view.context.startActivity(market)
                return true
            } catch (_: ActivityNotFoundException) {
                // Play 스토어도 없음 — 포기
            }
        }
        return false
    }

    override fun onPageFinished(view: WebView, url: String) {
        activity.onWebViewPageFinished()
    }

    private fun isInternal(uri: Uri): Boolean {
        val host = uri.host ?: return false
        return host == AppConfig.ALLOWED_HOST || host.endsWith(".${AppConfig.ALLOWED_HOST}") || host == "localhost" || host == "10.0.2.2"
    }

    companion object {
        private const val TAG = "MySaverWebView"
    }
}
