package com.capacitorjs.plugins.actionsheet

import android.annotation.SuppressLint
import android.app.Dialog
import android.content.DialogInterface
import android.graphics.Color
import android.view.View
import android.widget.LinearLayout
import android.widget.TextView
import androidx.coordinatorlayout.widget.CoordinatorLayout
import com.getcapacitor.Logger
import com.google.android.material.bottomsheet.BottomSheetBehavior
import com.google.android.material.bottomsheet.BottomSheetDialogFragment

public class ActionSheet : BottomSheetDialogFragment() {
    public fun interface OnSelectListener {
        public fun onSelect(index: Int)
    }

    public fun interface OnCancelListener {
        public fun onCancel()
    }

    public var title: String? = null
    public var options: Array<ActionSheetOption>? = null
    public var onSelectedListener: OnSelectListener? = null
    public var onCancelListener: OnCancelListener? = null

    private val bottomSheetCallback =
        object : BottomSheetBehavior.BottomSheetCallback() {
            override fun onStateChanged(bottomSheet: View, newState: Int) {
                if (newState == BottomSheetBehavior.STATE_HIDDEN) {
                    dismiss()
                }
            }

            override fun onSlide(bottomSheet: View, slideOffset: Float) {}
        }

    override fun onCancel(dialog: DialogInterface) {
        super.onCancel(dialog)
        onCancelListener?.onCancel()
    }

    @SuppressLint("RestrictedApi")
    override fun setupDialog(dialog: Dialog, style: Int) {
        super.setupDialog(dialog, style)

        val options = options ?: return
        val context = requireContext()

        val scale = resources.displayMetrics.density
        val padding16 = (16.0f * scale + 0.5f).toInt()
        val padding12 = (12.0f * scale + 0.5f).toInt()
        val padding8 = (8.0f * scale + 0.5f).toInt()

        val parentLayout = CoordinatorLayout(context)

        val layout = LinearLayout(context)
        layout.orientation = LinearLayout.VERTICAL
        layout.setPadding(padding16, padding16, padding16, padding16)
        if (title != null) {
            val titleView = TextView(context)
            titleView.setTextColor(Color.parseColor("#757575"))
            titleView.setPadding(padding8, padding8, padding8, padding8)
            titleView.text = title
            layout.addView(titleView)
        }

        options.forEachIndexed { index, option ->
            val optionView = TextView(context)
            optionView.setTextColor(Color.parseColor("#000000"))
            optionView.setPadding(padding12, padding12, padding12, padding12)
            optionView.text = option.title
            optionView.setOnClickListener {
                Logger.debug("CliCKED: $index")
                onSelectedListener?.onSelect(index)
            }
            layout.addView(optionView)
        }

        parentLayout.addView(layout.rootView)

        dialog.setContentView(parentLayout.rootView)

        val params = (parentLayout.parent as View).layoutParams as CoordinatorLayout.LayoutParams
        (params.behavior as? BottomSheetBehavior<*>)?.addBottomSheetCallback(bottomSheetCallback)
    }
}
