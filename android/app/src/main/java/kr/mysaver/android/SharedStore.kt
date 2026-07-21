package kr.mysaver.android

import android.content.Context

object SharedStore {
    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(AppConfig.PREFS_NAME, Context.MODE_PRIVATE)

    fun saveToken(context: Context, token: String) {
        prefs(context).edit().putString(AppConfig.KEY_TOKEN, token).apply()
    }

    fun clearToken(context: Context) {
        prefs(context).edit().remove(AppConfig.KEY_TOKEN).apply()
    }

    fun currentToken(context: Context): String? =
        prefs(context).getString(AppConfig.KEY_TOKEN, null)

    fun stashPendingShare(context: Context, url: String) {
        prefs(context).edit().putString(AppConfig.KEY_PENDING_SHARE, url).apply()
    }

    fun consumePendingShare(context: Context): String? {
        val p = prefs(context)
        val url = p.getString(AppConfig.KEY_PENDING_SHARE, null)
        if (url != null) p.edit().remove(AppConfig.KEY_PENDING_SHARE).apply()
        return url
    }
}
