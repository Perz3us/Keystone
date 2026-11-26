// SPDX-License-Identifier: GPL-3.0-or-later

package com.perz3us.keystone

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.text.format.DateUtils
import android.view.View
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import java.text.DateFormat

object WidgetDraw {
    private const val PREFS = "FlutterSharedPreferences"
    private const val P = "flutter.widget."
    const val STAMP = "${P}at"
    private val BARS = intArrayOf(R.id.widget_bar1, R.id.widget_bar2, R.id.widget_bar3, R.id.widget_bar4)
    private val METERS = intArrayOf(R.id.widget_meter_ok, R.id.widget_meter_warn, R.id.widget_meter_bad)

    fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun get(p: SharedPreferences, key: String): String = p.getString(P + key, "") ?: ""

    fun at(p: SharedPreferences): Long? = p.getString(STAMP, "")?.toLongOrNull()

    fun redrawAll(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        fun ids(c: Class<*>) = manager.getAppWidgetIds(ComponentName(context, c))
        ids(StatusWidget::class.java).let { if (it.isNotEmpty()) StatusWidget.draw(context, manager, it) }
        ids(DataWidget::class.java).let { if (it.isNotEmpty()) DataWidget.draw(context, manager, it) }
        ids(OverviewWidget::class.java).let { if (it.isNotEmpty()) OverviewWidget.draw(context, manager, it) }
    }

    fun tint(context: Context, views: RemoteViews, view: Int, res: Int, text: Boolean = false, default: Int? = null) {
        if (Build.VERSION.SDK_INT >= 31) {
            views.setColorStateList(view, if (text) "setTextColor" else "setImageTintList", res)
        } else if (res != default) {
            val c = ContextCompat.getColor(context, res)
            if (text) views.setTextColor(view, c) else views.setInt(view, "setColorFilter", c)
        }
    }

    fun text(views: RemoteViews, view: Int, value: String) {
        views.setTextViewText(view, value)
        views.setViewVisibility(view, if (value.isEmpty()) View.GONE else View.VISIBLE)
    }

    fun header(views: RemoteViews, title: String, at: Long?) {
        views.setTextViewText(R.id.widget_title, title)
        views.setTextViewText(
            R.id.widget_time,
            if (at == null) "" else DateUtils.formatSameDayTime(at, System.currentTimeMillis(), DateFormat.SHORT, DateFormat.SHORT),
        )
    }

    fun status(context: Context, views: RemoteViews, p: SharedPreferences) {
        val online = get(p, "online")
        views.setTextViewText(
            R.id.widget_status,
            when (online) {
                "1" -> "Online"
                "0" -> "Offline"
                else -> "Not checked"
            },
        )
        tint(context, views, R.id.widget_status, if (online == "0") R.color.widget_bad else R.color.widget_text, text = true, default = R.color.widget_text)
        val bars = get(p, "bars").toIntOrNull()?.coerceIn(0, 4)
        if (bars != null && online == "1") {
            val tone = when {
                bars >= 3 -> R.color.widget_ok
                bars == 2 -> R.color.widget_warn
                else -> R.color.widget_bad
            }
            BARS.forEachIndexed { i, id ->
                tint(context, views, id, if (i < bars) tone else R.color.widget_track, default = if (i < 3) R.color.widget_ok else R.color.widget_track)
            }
            views.setContentDescription(R.id.widget_bars, "Signal $bars of 4")
            views.setViewVisibility(R.id.widget_bars, View.VISIBLE)
        } else {
            views.setViewVisibility(R.id.widget_bars, View.GONE)
        }
    }

    fun meter(views: RemoteViews, pct: Int?) {
        val show = when {
            pct == null -> -1
            pct >= 100 -> 2
            pct >= 80 -> 1
            else -> 0
        }
        views.setViewVisibility(R.id.widget_meter_box, if (show < 0) View.GONE else View.VISIBLE)
        METERS.forEachIndexed { i, id ->
            views.setViewVisibility(id, if (i == show) View.VISIBLE else View.GONE)
            if (i == show) views.setProgressBar(id, 100, pct!!.coerceIn(0, 100), false)
        }
    }

    fun opensApp(context: Context, views: RemoteViews) {
        val open = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        views.setOnClickPendingIntent(android.R.id.background, open)
    }
}
