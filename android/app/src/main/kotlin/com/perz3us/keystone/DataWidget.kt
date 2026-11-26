// SPDX-License-Identifier: GPL-3.0-or-later

package com.perz3us.keystone

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import android.util.TypedValue
import android.widget.RemoteViews

class DataWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        draw(context, manager, ids)
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        draw(context, manager, intArrayOf(id))
    }

    companion object {
        fun draw(context: Context, manager: AppWidgetManager, ids: IntArray) {
            val p = WidgetDraw.prefs(context)
            if (Build.VERSION.SDK_INT >= 31) {
                manager.updateAppWidget(ids, RemoteViews(mapOf(SizeF(110f, 40f) to row(context, p), SizeF(110f, 110f) to full(context, p))))
                return
            }
            for (id in ids) {
                val tall = manager.getAppWidgetOptions(id).getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 110) >= 100
                manager.updateAppWidget(id, if (tall) full(context, p) else row(context, p))
            }
        }

        private fun full(context: Context, p: SharedPreferences): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.data_widget)
            val at = WidgetDraw.at(p)
            WidgetDraw.header(views, if (at == null) "Keystone" else WidgetDraw.get(p, "router").ifEmpty { "Data" }, at)
            val used = WidgetDraw.get(p, "used")
            val pct = WidgetDraw.get(p, "pct").toIntOrNull()
            val of = WidgetDraw.get(p, "of")
            val reset = WidgetDraw.get(p, "reset")
            when {
                at == null -> message(views, "Not set up", "Open the app")
                used.isEmpty() -> message(views, "No data yet", "Open the app")
                used == "Set a data plan" -> {
                    message(views, "No plan", used)
                    WidgetDraw.tint(context, views, R.id.widget_of, R.color.widget_accent, text = true, default = R.color.widget_muted)
                }
                pct == null -> {
                    lines(views, used, listOf(of, reset.replaceFirstChar { it.lowercase() }).filter { it.isNotEmpty() }.joinToString(" · "))
                    WidgetDraw.text(views, R.id.widget_split, WidgetDraw.get(p, "split"))
                }
                else -> lines(views, used, of, reset.removeSuffix(" left"))
            }
            WidgetDraw.meter(views, if (at == null || used.isEmpty()) null else pct)
            WidgetDraw.opensApp(context, views)
            return views
        }

        private fun message(views: RemoteViews, headline: String, detail: String) {
            lines(views, headline, detail)
            views.setTextViewTextSize(R.id.widget_used, TypedValue.COMPLEX_UNIT_SP, 22f)
        }

        private fun lines(views: RemoteViews, used: String, of: String, reset: String = "") {
            views.setTextViewText(R.id.widget_used, used)
            views.setTextViewTextSize(R.id.widget_used, TypedValue.COMPLEX_UNIT_SP, if (used.length > 7) 24f else 30f)
            WidgetDraw.text(views, R.id.widget_of, of)
            WidgetDraw.text(views, R.id.widget_reset, reset)
            WidgetDraw.text(views, R.id.widget_split, "")
        }

        private fun row(context: Context, p: SharedPreferences): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.data_widget_row)
            val at = WidgetDraw.at(p)
            val compact = WidgetDraw.get(p, "compact")
            views.setTextViewText(
                R.id.widget_compact,
                when {
                    at == null -> "Data · not set up"
                    compact.isNotEmpty() -> compact
                    else -> WidgetDraw.get(p, "used").ifEmpty { "No data yet" }
                },
            )
            WidgetDraw.meter(views, if (at == null) null else WidgetDraw.get(p, "pct").toIntOrNull())
            WidgetDraw.opensApp(context, views)
            return views
        }
    }
}
