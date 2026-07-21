package kr.mysaver.android

import android.content.Intent
import android.os.Bundle
import android.util.Patterns
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity

/**
 * Android Share intent 진입점.
 *
 * 흐름:
 * 1) SEND/SEND_MULTIPLE intent → URL 추출
 * 2) SharedPreferences 에 pending_share_url stash (메인앱 fallback 용)
 * 3) 토큰 없으면 메인앱 실행으로 위임
 * 4) 토큰 있으면 ShareSheetFragment (BottomSheetDialogFragment) 표시
 * 5) Fragment dismiss → finish
 *
 * UI 는 [ShareSheetFragment] 에 위임. API 는 [ShareApi] 분리.
 */
class ShareActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val url = extractUrl(intent)
        if (url == null) {
            toast("공유된 URL 을 찾을 수 없습니다")
            finish()
            return
        }
        SharedStore.stashPendingShare(this, url)

        val token = SharedStore.currentToken(this)
        if (token == null) {
            toast("MySaver 에서 로그인 후 동기화됩니다")
            startMainAppWith(url)
            finish()
            return
        }

        if (savedInstanceState != null) return  // 회전 등 → 기존 fragment 유지

        val fragment = ShareSheetFragment.newInstance(url = url, token = token).apply {
            onDismissCallback = { finish() }
        }
        fragment.show(supportFragmentManager, "share-sheet")
    }

    // MARK: - URL 추출

    private fun extractUrl(intent: Intent?): String? {
        intent ?: return null
        return when (intent.action) {
            Intent.ACTION_SEND -> {
                val text = intent.getStringExtra(Intent.EXTRA_TEXT) ?: return null
                firstUrl(text)
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                intent.getStringArrayListExtra(Intent.EXTRA_TEXT)
                    ?.asSequence()
                    ?.mapNotNull { firstUrl(it) }
                    ?.firstOrNull()
            }
            else -> null
        }
    }

    private fun firstUrl(text: String): String? {
        val matcher = Patterns.WEB_URL.matcher(text)
        return if (matcher.find()) matcher.group() else null
    }

    private fun startMainAppWith(url: String) {
        val intent = Intent(this, MainActivity::class.java).apply {
            putExtra(MainActivity.EXTRA_SHARED_URL, url)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        startActivity(intent)
    }

    private fun toast(text: String) {
        Toast.makeText(this, text, Toast.LENGTH_SHORT).show()
    }
}
