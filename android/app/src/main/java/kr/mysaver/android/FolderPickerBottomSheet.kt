package kr.mysaver.android

import android.app.Dialog
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.view.isVisible
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.bottomsheet.BottomSheetBehavior
import com.google.android.material.bottomsheet.BottomSheetDialog
import com.google.android.material.bottomsheet.BottomSheetDialogFragment

/**
 * ShareSheetFragment 의 📁 버튼 탭 시 표시되는 폴더 선택 시트.
 */
class FolderPickerBottomSheet : BottomSheetDialogFragment() {

    private var folders: List<ShareApi.FolderInfo> = emptyList()
    private var selectedId: Int? = null
    private var onPick: ((ShareApi.FolderInfo?) -> Unit)? = null

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
    ): View = inflater.inflate(R.layout.fragment_folder_picker, container, false)

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        val cancelText = view.findViewById<TextView>(R.id.cancel_text)
        val emptyState = view.findViewById<LinearLayout>(R.id.empty_state)
        val recycler = view.findViewById<RecyclerView>(R.id.folder_list)

        cancelText.setOnClickListener { dismissAllowingStateLoss() }

        if (folders.isEmpty()) {
            emptyState.isVisible = true
            recycler.isVisible = false
            return
        }

        emptyState.isVisible = false
        recycler.isVisible = true
        recycler.layoutManager = LinearLayoutManager(requireContext())
        recycler.adapter = FolderAdapter(
            folders = folders,
            selectedId = selectedId,
            onClick = { folder ->
                onPick?.invoke(folder)
                dismissAllowingStateLoss()
            }
        )
    }

    private class FolderAdapter(
        private val folders: List<ShareApi.FolderInfo>,
        private val selectedId: Int?,
        private val onClick: (ShareApi.FolderInfo?) -> Unit,
    ) : RecyclerView.Adapter<FolderAdapter.VH>() {

        private val items: List<ShareApi.FolderInfo?> = listOf(null) + folders

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH {
            val v = LayoutInflater.from(parent.context).inflate(
                R.layout.item_folder_picker, parent, false
            )
            return VH(v)
        }

        override fun getItemCount(): Int = items.size

        override fun onBindViewHolder(holder: VH, position: Int) {
            val folder = items[position]
            if (folder == null) {
                holder.emoji.text = "∅"
                holder.name.text = "폴더 없이 저장"
                holder.check.isVisible = selectedId == null
            } else {
                holder.emoji.text = folder.emoji ?: "📁"
                holder.name.text = folder.name
                holder.check.isVisible = selectedId == folder.id
            }
            holder.itemView.setOnClickListener { onClick(folder) }
        }

        class VH(itemView: View) : RecyclerView.ViewHolder(itemView) {
            val emoji: TextView = itemView.findViewById(R.id.emoji_text)
            val name: TextView = itemView.findViewById(R.id.name_text)
            val check: ImageView = itemView.findViewById(R.id.check_icon)
        }
    }

    companion object {
        fun newInstance(
            folders: List<ShareApi.FolderInfo>,
            selectedId: Int?,
            onPick: (ShareApi.FolderInfo?) -> Unit,
        ): FolderPickerBottomSheet {
            return FolderPickerBottomSheet().apply {
                this.folders = folders
                this.selectedId = selectedId
                this.onPick = onPick
            }
        }
    }
}
