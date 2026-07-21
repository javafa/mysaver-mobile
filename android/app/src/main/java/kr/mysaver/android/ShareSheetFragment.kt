package kr.mysaver.android

import android.app.Dialog
import android.os.Bundle
import android.text.Editable
import android.text.TextWatcher
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.ProgressBar
import android.widget.TextView
import androidx.core.view.isVisible
import androidx.fragment.app.viewModels
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import coil.load
import com.google.android.material.bottomsheet.BottomSheetBehavior
import com.google.android.material.bottomsheet.BottomSheetDialog
import com.google.android.material.bottomsheet.BottomSheetDialogFragment
import com.google.android.material.button.MaterialButton
import kotlinx.coroutines.launch

/**
 * 와이어프레임의 "After" 디자인. ShareActivity 에서 호출.
 *
 * 표시: 썸네일 + 제목/메타 + 태그 + 노트 + 리마인드(UI only) + CTA/폴더/취소 바텀바.
 */
class ShareSheetFragment : BottomSheetDialogFragment() {

    private val viewModel: SharePreviewViewModel by viewModels {
        viewModelFactory {
            initializer {
                val args = requireArguments()
                SharePreviewViewModel(
                    sharedUrl = args.getString(ARG_URL).orEmpty(),
                    token = args.getString(ARG_TOKEN),
                )
            }
        }
    }

    /** ShareActivity 가 dismiss 후 finish 하도록 콜백. */
    var onDismissCallback: (() -> Unit)? = null

    override fun onCreateDialog(savedInstanceState: Bundle?): Dialog {
        val dialog = BottomSheetDialog(requireContext(), theme)
        dialog.setOnShowListener {
            val sheet = dialog.findViewById<FrameLayout>(
                com.google.android.material.R.id.design_bottom_sheet
            )
            sheet?.let {
                BottomSheetBehavior.from(it).apply {
                    state = BottomSheetBehavior.STATE_EXPANDED
                    skipCollapsed = true
                }
            }
        }
        return dialog
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View = inflater.inflate(R.layout.fragment_share_sheet, container, false)

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        val closeBtn = view.findViewById<ImageButton>(R.id.close_btn)
        val thumbnailView = view.findViewById<ImageView>(R.id.thumbnail_view)
        val thumbnailProgress = view.findViewById<ProgressBar>(R.id.thumbnail_progress)
        val thumbnailPlaceholder = view.findViewById<TextView>(R.id.thumbnail_placeholder)
        val titleText = view.findViewById<TextView>(R.id.title_text)
        val metaText = view.findViewById<TextView>(R.id.meta_text)
        val noteInput = view.findViewById<EditText>(R.id.note_input)
        val statusText = view.findViewById<TextView>(R.id.status_text)
        val ctaBtn = view.findViewById<MaterialButton>(R.id.cta_btn)
        val folderBtn = view.findViewById<MaterialButton>(R.id.folder_btn)
        val cancelBtn = view.findViewById<MaterialButton>(R.id.cancel_btn)

        closeBtn.setOnClickListener { dismissAllowingStateLoss() }
        cancelBtn.setOnClickListener { dismissAllowingStateLoss() }

        noteInput.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
            override fun afterTextChanged(s: Editable?) {
                val current = viewModel.state.value.note
                val next = s?.toString().orEmpty()
                if (current != next) viewModel.setNote(next)
            }
        })

        folderBtn.setOnClickListener {
            val state = viewModel.state.value
            FolderPickerBottomSheet.newInstance(
                folders = state.folders,
                selectedId = state.selectedFolder?.id,
            ) { folder ->
                viewModel.setSelectedFolder(folder)
            }.show(parentFragmentManager, "folder-picker")
        }

        ctaBtn.setOnClickListener {
            ctaBtn.isEnabled = false
            lifecycleScope.launch {
                val ok = viewModel.save()
                if (ok) {
                    kotlinx.coroutines.delay(600)
                    dismissAllowingStateLoss()
                } else {
                    ctaBtn.isEnabled = true
                }
            }
        }

        viewLifecycleOwner.lifecycleScope.launch {
            viewLifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
                viewModel.state.collect { state ->
                    // 썸네일
                    val ogUrl = state.ogImageUrl
                    if (ogUrl != null) {
                        thumbnailProgress.isVisible = false
                        thumbnailPlaceholder.isVisible = false
                        thumbnailView.isVisible = true
                        thumbnailView.load(ogUrl) {
                            crossfade(true)
                        }
                    } else if (state.isPreviewLoading) {
                        thumbnailProgress.isVisible = true
                        thumbnailPlaceholder.isVisible = false
                        thumbnailView.isVisible = false
                    } else {
                        thumbnailProgress.isVisible = false
                        thumbnailPlaceholder.isVisible = true
                        thumbnailView.isVisible = false
                    }

                    // 제목/메타
                    titleText.text = state.displayTitle
                    metaText.text = "${state.domain} · ${viewModel.displayDate()}"

                    // CTA 라벨
                    ctaBtn.text = state.selectedFolder?.let { "‘${it.name}'에 추가하기" } ?: "추가하기"
                    folderBtn.text = state.selectedFolder?.emoji ?: "📁"

                    // 상태 메시지
                    when (val s = state.saveStatus) {
                        SharePreviewViewModel.SaveStatus.Idle -> {
                            statusText.isVisible = false
                        }
                        SharePreviewViewModel.SaveStatus.Saving -> {
                            statusText.isVisible = true
                            statusText.text = "저장 중…"
                            statusText.setTextColor(0xFF6B7280.toInt())
                        }
                        is SharePreviewViewModel.SaveStatus.Success -> {
                            statusText.isVisible = true
                            statusText.text = "✓ ${s.message}"
                            statusText.setTextColor(0xFF16A34A.toInt())
                            // sync 성공: pending 제거
                            SharedStore.consumePendingShare(requireContext())
                        }
                        is SharePreviewViewModel.SaveStatus.Failure -> {
                            statusText.isVisible = true
                            statusText.text = "⚠ ${s.message}"
                            statusText.setTextColor(0xFFE65100.toInt())
                        }
                    }
                }
            }
        }
    }

    override fun onDismiss(dialog: android.content.DialogInterface) {
        super.onDismiss(dialog)
        onDismissCallback?.invoke()
    }

    companion object {
        private const val ARG_URL = "arg_url"
        private const val ARG_TOKEN = "arg_token"

        fun newInstance(url: String, token: String?): ShareSheetFragment {
            return ShareSheetFragment().apply {
                arguments = Bundle().apply {
                    putString(ARG_URL, url)
                    putString(ARG_TOKEN, token)
                }
            }
        }
    }
}
