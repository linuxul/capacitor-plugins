package com.capacitorjs.plugins.camera

import android.annotation.SuppressLint
import android.app.Dialog
import android.content.DialogInterface
import android.graphics.Color
import android.view.View
import android.widget.LinearLayout
import android.widget.TextView
import androidx.coordinatorlayout.widget.CoordinatorLayout
import com.google.android.material.bottomsheet.BottomSheetBehavior
import com.google.android.material.bottomsheet.BottomSheetDialogFragment

public class CameraBottomSheetDialogFragment : BottomSheetDialogFragment() {
    internal fun interface BottomSheetOnSelectedListener {
        fun onSelected(index: Int)
    }

    internal fun interface BottomSheetOnCanceledListener {
        fun onCanceled()
    }

    private var selectedListener: BottomSheetOnSelectedListener? = null
    private var canceledListener: BottomSheetOnCanceledListener? = null
    private var options: List<String?>? = null

    internal var title: String? = null

    internal fun setOptions(
        options: List<String?>,
        selectedListener: BottomSheetOnSelectedListener,
        canceledListener: BottomSheetOnCanceledListener
    ) {
        this.options = options
        this.selectedListener = selectedListener
        this.canceledListener = canceledListener
    }

    override fun onCancel(dialog: DialogInterface) {
        super.onCancel(dialog)
        canceledListener?.onCanceled()
    }

    private val bottomSheetBehaviorCallback =
        object : BottomSheetBehavior.BottomSheetCallback() {
            override fun onStateChanged(bottomSheet: View, newState: Int) {
                if (newState == BottomSheetBehavior.STATE_HIDDEN) {
                    dismiss()
                }
            }

            override fun onSlide(bottomSheet: View, slideOffset: Float) {}
        }

    @SuppressLint("RestrictedApi")
    override fun setupDialog(dialog: Dialog, style: Int) {
        super.setupDialog(dialog, style)

        val options = options
        if (options.isNullOrEmpty()) {
            return
        }

        val context = requireContext()
        val scale = resources.displayMetrics.density

        val layoutPaddingPx16 = (16.0f * scale + 0.5f).toInt()
        val layoutPaddingPx12 = (12.0f * scale + 0.5f).toInt()
        val layoutPaddingPx8 = (8.0f * scale + 0.5f).toInt()

        val parentLayout = CoordinatorLayout(context)

        val layout = LinearLayout(context)
        layout.orientation = LinearLayout.VERTICAL
        layout.setPadding(layoutPaddingPx16, layoutPaddingPx16, layoutPaddingPx16, layoutPaddingPx16)

        val ttv = TextView(context)
        ttv.setTextColor(Color.parseColor("#757575"))
        ttv.setPadding(layoutPaddingPx8, layoutPaddingPx8, layoutPaddingPx8, layoutPaddingPx8)
        ttv.text = title
        layout.addView(ttv)

        for ((optionIndex, option) in options.withIndex()) {
            val tv = TextView(context)
            tv.setTextColor(Color.parseColor("#000000"))
            tv.setPadding(layoutPaddingPx12, layoutPaddingPx12, layoutPaddingPx12, layoutPaddingPx12)
            tv.text = option
            tv.setOnClickListener {
                selectedListener?.onSelected(optionIndex)
                dismiss()
            }
            layout.addView(tv)
        }

        parentLayout.addView(layout.rootView)

        dialog.setContentView(parentLayout.rootView)

        val params = (parentLayout.parent as View).layoutParams as CoordinatorLayout.LayoutParams
        val behavior = params.behavior

        if (behavior is BottomSheetBehavior<*>) {
            behavior.addBottomSheetCallback(bottomSheetBehaviorCallback)
            behavior.state = BottomSheetBehavior.STATE_EXPANDED
        }
    }
}
