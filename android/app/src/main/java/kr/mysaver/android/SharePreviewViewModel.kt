package kr.mysaver.android

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID

/**
 * ShareSheetFragment 의 상태 홀더.
 * Preview / 폴더 목록 / 노트 / 저장 상태.
 */
class SharePreviewViewModel(
    val sharedUrl: String,
    private val token: String?,
) : ViewModel() {

    sealed interface SaveStatus {
        data object Idle : SaveStatus
        data object Saving : SaveStatus
        data class Success(val message: String) : SaveStatus
        data class Failure(val message: String) : SaveStatus
    }

    data class UiState(
        val isPreviewLoading: Boolean = true,
        val title: String? = null,
        val domain: String = "",
        val ogImageUrl: String? = null,
        val platform: String = "unknown",
        val contentType: String = "link",
        val folders: List<ShareApi.FolderInfo> = emptyList(),
        val selectedFolder: ShareApi.FolderInfo? = null,
        val note: String = "",
        val tags: List<String> = emptyList(),
        val saveStatus: SaveStatus = SaveStatus.Idle,
    ) {
        val displayTitle: String get() = title?.takeIf { it.isNotEmpty() } ?: "(제목 없음)"
        val isSaving: Boolean get() = saveStatus is SaveStatus.Saving
    }

    private val _state = MutableStateFlow(
        UiState(
            domain = try { URL(sharedUrl).host ?: "" } catch (_: Exception) { "" },
            platform = ShareApi.detectPlatform(sharedUrl),
        )
    )
    val state: StateFlow<UiState> = _state.asStateFlow()

    fun displayDate(): String {
        val fmt = SimpleDateFormat("yyyy. M. d.", Locale.KOREA)
        return fmt.format(Date())
    }

    init {
        loadPreview()
        loadFolders()
    }

    fun setNote(note: String) {
        _state.update { it.copy(note = note) }
    }

    fun setSelectedFolder(folder: ShareApi.FolderInfo?) {
        _state.update { it.copy(selectedFolder = folder) }
    }

    private fun loadPreview() {
        val token = this.token
        if (token == null) {
            _state.update { it.copy(isPreviewLoading = false) }
            return
        }
        viewModelScope.launch {
            val preview = ShareApi.fetchPreview(sharedUrl, token)
            _state.update { current ->
                if (preview == null) {
                    current.copy(isPreviewLoading = false)
                } else {
                    current.copy(
                        isPreviewLoading = false,
                        title = preview.title,
                        domain = preview.domain.ifEmpty { current.domain },
                        ogImageUrl = preview.ogImageUrl,
                        platform = preview.platform,
                        contentType = preview.contentType,
                    )
                }
            }
        }
    }

    private fun loadFolders() {
        val token = this.token ?: return
        viewModelScope.launch {
            val folders = ShareApi.fetchFolders(token)
            _state.update { it.copy(folders = folders) }
        }
    }

    /** "추가하기" 탭 시. 성공 시 true 반환. */
    suspend fun save(): Boolean {
        val token = this.token ?: run {
            _state.update { it.copy(saveStatus = SaveStatus.Failure("로그인 후 이용해주세요")) }
            return false
        }
        _state.update { it.copy(saveStatus = SaveStatus.Saving) }
        val itemId = UUID.randomUUID().toString()
        val current = _state.value
        val syncOk = ShareApi.postSync(
            itemId = itemId,
            url = sharedUrl,
            domain = current.domain,
            platform = current.platform,
            contentType = current.contentType,
            title = current.title,
            note = current.note.ifEmpty { null },
            tags = current.tags,
            thumbnailUrl = current.ogImageUrl,
            token = token,
        )
        if (!syncOk) {
            _state.update { it.copy(saveStatus = SaveStatus.Failure("저장 실패 — 앱을 열면 재시도됩니다")) }
            return false
        }
        val folder = current.selectedFolder
        if (folder != null) {
            val linkOk = ShareApi.postFolderLink(folder.id, itemId, token)
            if (linkOk) {
                _state.update { it.copy(saveStatus = SaveStatus.Success("'${folder.name}'에 저장됨")) }
            } else {
                _state.update { it.copy(saveStatus = SaveStatus.Failure("폴더 연결 실패 — 앱에서 확인해주세요")) }
                return false
            }
        } else {
            _state.update { it.copy(saveStatus = SaveStatus.Success("저장됨")) }
        }
        return true
    }
}
