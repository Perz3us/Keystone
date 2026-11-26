// SPDX-License-Identifier: GPL-3.0-or-later

package com.perz3us.keystone

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.view.View
import android.widget.RemoteViews

class StatusWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        draw(context, manager, ids)
    }

    companion object {
        fun draw(context: Context, manager: AppWidgetManager, ids: IntArray) {
            val p = WidgetDraw.prefs(context)
            val at = WidgetDraw.at(p)
            val views = RemoteViews(context.packageName, R.layout.status_widget)
            if (at == null) {
                WidgetDraw.header(views, "Keystone", null)
                views.setTextViewText(R.id.widget_status, "Not set up")
                WidgetDraw.tint(context, views, R.id.widget_status, R.color.widget_text, text = true)
                views.setTextViewText(R.id.widget_data, "Open the app")
                views.setViewVisibility(R.id.widget_bars, View.GONE)
            } else {
                WidgetDraw.header(views, WidgetDraw.get(p, "router").ifEmpty { "Router" }, at)
                WidgetDraw.status(context, views, p)
                views.setTextViewText(R.id.widget_data, WidgetDraw.get(p, "data"))
            }
            WidgetDraw.opensApp(context, views)
            manager.updateAppWidget(ids, views)
        }
    }
}
