// SPDX-License-Identifier: GPL-3.0-or-later

package com.perz3us.keystone

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.view.View
import android.widget.RemoteViews

class OverviewWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        draw(context, manager, ids)
    }

    companion object {
        fun draw(context: Context, manager: AppWidgetManager, ids: IntArray) {
            val p = WidgetDraw.prefs(context)
            val at = WidgetDraw.at(p)
            val views = RemoteViews(context.packageName, R.layout.overview_widget)
            if (at == null) {
                WidgetDraw.header(views, "Keystone", null)
                views.setTextViewText(R.id.widget_status, "Not set up")
                WidgetDraw.tint(context, views, R.id.widget_status, R.color.widget_text, text = true)
                views.setViewVisibility(R.id.widget_bars, View.GONE)
                WidgetDraw.text(views, R.id.widget_signal, "")
                WidgetDraw.text(views, R.id.widget_compact, "Open the app")
                WidgetDraw.meter(views, null)
            } else {
                WidgetDraw.header(views, WidgetDraw.get(p, "router").ifEmpty { "Router" }, at)
                WidgetDraw.status(context, views, p)
                WidgetDraw.text(views, R.id.widget_signal, WidgetDraw.get(p, "signal"))
                val compact = WidgetDraw.get(p, "compact")
                val used = WidgetDraw.get(p, "used")
                WidgetDraw.text(views, R.id.widget_compact, compact.ifEmpty { used })
                if (compact.isEmpty() && used == "Set a data plan") {
                    WidgetDraw.tint(context, views, R.id.widget_compact, R.color.widget_accent, text = true, default = R.color.widget_body)
                }
                WidgetDraw.meter(views, WidgetDraw.get(p, "pct").toIntOrNull())
            }
            WidgetDraw.opensApp(context, views)
            manager.updateAppWidget(ids, views)
        }
    }
}
