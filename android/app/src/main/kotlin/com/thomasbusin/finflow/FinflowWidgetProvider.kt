package com.thomasbusin.finflow

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Widget d'écran d'accueil : disponible estimé du mois et soldes.
 *
 * Les textes sont déjà formatés côté Flutter (lib/core/home_widget_sync.dart)
 * et lus ici depuis les SharedPreferences de home_widget. Toucher le widget
 * ouvre l'app.
 */
class FinflowWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.finflow_widget).apply {
                setTextViewText(R.id.widget_month, widgetData.getString("month", "FinFlow"))
                setTextViewText(
                    R.id.widget_available,
                    widgetData.getString("available", "—"),
                )
                setTextViewText(
                    R.id.widget_balances,
                    widgetData.getString("balances", "Ouvre FinFlow pour charger tes soldes"),
                )
                setTextViewText(R.id.widget_updated, widgetData.getString("updated", ""))
                setOnClickPendingIntent(
                    R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
                )
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
