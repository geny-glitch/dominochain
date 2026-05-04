package com.bg

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.util.AttributeSet
import android.view.View
import androidx.core.content.ContextCompat
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.max

/**
 * Histogramme simple pour les 7 derniers jours (du plus ancien à gauche au jour courant à droite).
 */
class CigaretteHistoryBarChartView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : View(context, attrs, defStyleAttr) {

    private val barPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = ContextCompat.getColor(context, R.color.ds_teal_dim)
        style = Paint.Style.FILL
    }
    private val barHighlightPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = ContextCompat.getColor(context, R.color.ds_teal)
        style = Paint.Style.FILL
    }
    private val gridPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = ContextCompat.getColor(context, R.color.ds_border)
        style = Paint.Style.STROKE
        strokeWidth = 1f * resources.displayMetrics.density
    }
    private val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = ContextCompat.getColor(context, R.color.ds_text_muted)
        textSize = 11f * resources.displayMetrics.scaledDensity
        textAlign = Paint.Align.CENTER
    }
    private val valuePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = ContextCompat.getColor(context, R.color.ds_text)
        textSize = 11f * resources.displayMetrics.scaledDensity
        textAlign = Paint.Align.CENTER
    }

    private val dayFormatter = DateTimeFormatter.ofPattern("EEE", Locale.FRENCH)
    private val barRect = RectF()

    private var entries: List<BarEntry> = emptyList()
    private var chartBottom = 0f
    private var chartTop = 0f

    data class BarEntry(val date: LocalDate, val count: Int, val isToday: Boolean)

    fun setEntries(entries: List<BarEntry>) {
        this.entries = entries
        invalidate()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val minH = (MIN_HEIGHT_DP * resources.displayMetrics.density).toInt()
        val h = resolveSize(minH, heightMeasureSpec)
        super.onMeasure(widthMeasureSpec, MeasureSpec.makeMeasureSpec(h, MeasureSpec.EXACTLY))
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val w = width.toFloat()
        val h = height.toFloat()
        val pad = 8f * resources.displayMetrics.density
        chartBottom = h - pad - labelPaint.textSize - 6f * resources.displayMetrics.density
        chartTop = pad + valuePaint.textSize + 4f * resources.displayMetrics.density

        if (entries.isEmpty()) {
            canvas.drawText(context.getString(R.string.tracker_cigarettes_chart_empty), w / 2f, h / 2f, labelPaint)
            return
        }

        canvas.drawLine(pad, chartBottom, w - pad, chartBottom, gridPaint)

        val maxCount = entries.maxOfOrNull { it.count } ?: 0
        val scaleMax = max(maxCount, 1)
        val chartHeight = chartBottom - chartTop
        val n = entries.size
        val slotW = (w - 2 * pad) / n
        val barW = slotW * 0.55f

        entries.forEachIndexed { i, e ->
            val cx = pad + slotW * (i + 0.5f)
            val barHeight = chartHeight * e.count / scaleMax
            val left = cx - barW / 2f
            val top = chartBottom - barHeight
            val right = cx + barW / 2f
            barRect.set(left, top, right, chartBottom)
            canvas.drawRoundRect(barRect, 4f * resources.displayMetrics.density, 4f * resources.displayMetrics.density,
                if (e.isToday) barHighlightPaint else barPaint)

            if (e.count > 0) {
                val vs = e.count.toString()
                val ty = top - 4f * resources.displayMetrics.density
                if (ty > chartTop) {
                    canvas.drawText(vs, cx, ty, valuePaint)
                }
            }

            val dayLabel = e.date.format(dayFormatter)
            canvas.drawText(dayLabel, cx, h - pad, labelPaint)
        }
    }

    companion object {
        private const val MIN_HEIGHT_DP = 168f
    }
}
