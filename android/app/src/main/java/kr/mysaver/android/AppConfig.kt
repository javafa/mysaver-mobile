package kr.mysaver.android

object AppConfig {
    const val SITE_URL = "https://mysaver.kr"
    const val ALLOWED_HOST = "mysaver.kr"
    // prod API 호스트는 api.mysaver.kr (별도 서브도메인). SITE_URL 과 다름.
    const val API_BASE = "https://api.mysaver.kr"

    // 로컬 개발 서버: SITE_URL = "http://10.0.2.2:3000" (Android emulator → host localhost)
    // 그리고 AndroidManifest 에 android:usesCleartextTraffic="true" 필요.

    const val PREFS_NAME = "mysaver_prefs"
    const val KEY_TOKEN = "auth_token"
    const val KEY_PENDING_SHARE = "pending_share_url"

    const val URL_SCHEME = "mysaver"
    const val OAUTH_CALLBACK_HOST = "oauth"
}
