// SPDX-License-Identifier: GPL-3.0-or-later

package com.perz3us.keystone

import android.app.Application
import android.content.SharedPreferences
import android.content.res.Configuration

class KeystoneApp : Application() {
    private val widgetListener = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
        if (key == WidgetDraw.STAMP) WidgetDraw.redrawAll(this)
    }

    override fun onCreate() {
        super.onCreate()
        WidgetDraw.prefs(this).registerOnSharedPreferenceChangeListener(widgetListener)
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        WidgetDraw.redrawAll(this)
    }
}
