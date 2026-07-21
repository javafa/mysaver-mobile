package kr.mysaver.android

import android.net.Uri
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Share Activity 가 호출하는 백엔드 API.
 * 기존 ShareActivity 의 인라인 호출을 분리.
 */
object ShareApi {

    data class FolderInfo(
        val id: Int,
        val name: String,
        val emoji: String?,
        val color: String?,
    )

    data class PreviewInfo(
        val url: String,
        val domain: String,
        val title: String?,
        val ogImageUrl: String?,
        val platform: String,
        val contentType: String,
    )

    // --- GET /api/items/preview ---

    suspend fun fetchPreview(url: String, token: String): PreviewInfo? = withContext(Dispatchers.IO) {
        // YouTube 는 oEmbed 직접 호출 — 봇 차단 / 백엔드 지연 무관, 한 hop 단축.
        // 실패 시 백엔드 폴백.
        if (isYouTubeUrl(url)) {
            val oembed = fetchYouTubeOEmbedBlocking(url)
            if (oembed != null) return@withContext oembed
        }

        try {
            val encoded = Uri.encode(url)
            val endpoint = URL("${AppConfig.API_BASE}/api/items/preview?url=$encoded")
            val conn = endpoint.openConnection() as HttpURLConnection
            conn.requestMethod = "GET"
            conn.connectTimeout = 5000
            conn.readTimeout = 5000
            conn.setRequestProperty("Authorization", "Bearer $token")

            if (conn.responseCode !in 200..299) {
                conn.disconnect()
                return@withContext null
            }
            val body = conn.inputStream.bufferedReader().use { it.readText() }
            conn.disconnect()

            val o = JSONObject(body)
            PreviewInfo(
                url = o.optString("url", url),
                domain = o.optString("domain", ""),
                title = o.optString("title", "").takeIf { it.isNotEmpty() && it != "null" },
                ogImageUrl = o.optString("ogImageUrl", "").takeIf { it.isNotEmpty() && it != "null" },
                platform = o.optString("platform", "unknown"),
                contentType = o.optString("contentType", "link"),
            )
        } catch (_: Exception) {
            null
        }
    }

    // --- YouTube oEmbed (백엔드 우회) ---

    private fun isYouTubeUrl(url: String): Boolean = try {
        val host = URL(url).host?.lowercase() ?: ""
        host.contains("youtube.com") || host == "youtu.be"
    } catch (_: Exception) {
        false
    }

    /** Dispatchers.IO 위에서 호출되는 blocking 함수. */
    private fun fetchYouTubeOEmbedBlocking(url: String): PreviewInfo? = try {
        val encoded = Uri.encode(url)
        val endpoint = URL("https://www.youtube.com/oembed?url=$encoded&format=json")
        val conn = endpoint.openConnection() as HttpURLConnection
        conn.requestMethod = "GET"
        conn.connectTimeout = 4000
        conn.readTimeout = 4000
        if (conn.responseCode !in 200..299) {
            conn.disconnect()
            null
        } else {
            val body = conn.inputStream.bufferedReader().use { it.readText() }
            conn.disconnect()
            val o = JSONObject(body)
            val domain = try { URL(url).host ?: "" } catch (_: Exception) { "" }
            PreviewInfo(
                url = url,
                domain = domain,
                title = o.optString("title", "").takeIf { it.isNotEmpty() && it != "null" },
                ogImageUrl = o.optString("thumbnail_url", "").takeIf { it.isNotEmpty() && it != "null" },
                platform = "youtube",
                contentType = "video",
            )
        }
    } catch (_: Exception) {
        null
    }

    // --- GET /api/folders/ ---

    suspend fun fetchFolders(token: String): List<FolderInfo> = withContext(Dispatchers.IO) {
        try {
            val endpoint = URL("${AppConfig.API_BASE}/api/folders/")
            val conn = endpoint.openConnection() as HttpURLConnection
            conn.requestMethod = "GET"
            conn.connectTimeout = 8000
            conn.readTimeout = 8000
            conn.setRequestProperty("Authorization", "Bearer $token")

            if (conn.responseCode !in 200..299) {
                conn.disconnect()
                return@withContext emptyList()
            }
            val body = conn.inputStream.bufferedReader().use { it.readText() }
            conn.disconnect()

            val arr = JSONArray(body)
            buildList {
                for (i in 0 until arr.length()) {
                    val o = arr.getJSONObject(i)
                    add(
                        FolderInfo(
                            id = o.getInt("id"),
                            name = o.getString("name"),
                            emoji = o.optString("emoji", "").takeIf { it.isNotEmpty() && it != "null" },
                            color = o.optString("color", "").takeIf { it.isNotEmpty() && it != "null" },
                        )
                    )
                }
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    // --- POST /api/items/sync ---

    suspend fun postSync(
        itemId: String,
        url: String,
        domain: String,
        platform: String,
        contentType: String,
        title: String?,
        note: String?,
        tags: List<String>,
        thumbnailUrl: String?,
        token: String,
    ): Boolean = withContext(Dispatchers.IO) {
        try {
            val endpoint = URL("${AppConfig.API_BASE}/api/items/sync")
            val conn = endpoint.openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.connectTimeout = 10000
            conn.readTimeout = 10000
            conn.doOutput = true
            conn.setRequestProperty("Content-Type", "application/json")
            conn.setRequestProperty("Authorization", "Bearer $token")

            val now = iso8601Now()
            val item = JSONObject().apply {
                put("id", itemId)
                put("url", url)
                put("domain", domain)
                put("platform", platform)
                put("contentType", contentType)
                put("createdAt", now)
                put("updatedAt", now)
                put("source", "share-android")
                put("metadataSource", if (title != null || thumbnailUrl != null) "og" else "minimal")
                put("tags", JSONArray(tags))
                if (title != null) put("title", title)
                if (note != null) put("note", note)
                if (thumbnailUrl != null) put("thumbnailUrl", thumbnailUrl)
            }
            val body = JSONObject().apply {
                put("items", JSONArray().apply { put(item) })
            }
            conn.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
            val code = conn.responseCode
            conn.disconnect()
            code in 200..299
        } catch (_: Exception) {
            false
        }
    }

    // --- POST /api/folders/{id}/items ---

    suspend fun postFolderLink(folderId: Int, itemId: String, token: String): Boolean = withContext(Dispatchers.IO) {
        try {
            val endpoint = URL("${AppConfig.API_BASE}/api/folders/$folderId/items")
            val conn = endpoint.openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.connectTimeout = 8000
            conn.readTimeout = 8000
            conn.doOutput = true
            conn.setRequestProperty("Content-Type", "application/json")
            conn.setRequestProperty("Authorization", "Bearer $token")

            val body = JSONObject().apply { put("itemId", itemId) }
            conn.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
            val code = conn.responseCode
            conn.disconnect()
            code in 200..299
        } catch (_: Exception) {
            false
        }
    }

    private fun iso8601Now(): String {
        val fmt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US)
        fmt.timeZone = TimeZone.getTimeZone("UTC")
        return fmt.format(Date())
    }

    fun detectPlatform(url: String): String {
        val host = try { URL(url).host?.lowercase() ?: "" } catch (_: Exception) { "" }
        return when {
            host.contains("youtube.com") || host.contains("youtu.be") -> "youtube"
            host.contains("instagram.com") -> "instagram"
            host.contains("pinterest.") -> "pinterest"
            else -> "unknown"
        }
    }
}
