package com.example.vibe_local

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.view.KeyEvent
import android.widget.RemoteViews
import java.io.File

class VibeWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (widgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, widgetId, lastTitle, lastArtist, lastIsPlaying)
        }
    }

    companion object {
        var lastTitle: String = "Vibe Local"
        var lastArtist: String = "Nada en reproducción"
        var lastIsPlaying: Boolean = false

        fun updateAll(context: Context, title: String, artist: String, isPlaying: Boolean, coverPath: String?) {
            lastTitle = title
            lastArtist = artist
            lastIsPlaying = isPlaying

            val appWidgetManager = AppWidgetManager.getInstance(context)
            val thisWidget = ComponentName(context, VibeWidgetProvider::class.java)
            val allWidgetIds = appWidgetManager.getAppWidgetIds(thisWidget)

            for (widgetId in allWidgetIds) {
                updateAppWidget(context, appWidgetManager, widgetId, title, artist, isPlaying)
            }
        }

        private fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
            title: String,
            artist: String,
            isPlaying: Boolean
        ) {
            val views = RemoteViews(context.packageName, R.layout.vibe_widget)

            views.setTextViewText(R.id.widget_title, title)
            views.setTextViewText(R.id.widget_artist, artist)

            // Play / Pause Icon
            val playIcon = if (isPlaying) {
                android.R.drawable.ic_media_pause
            } else {
                android.R.drawable.ic_media_play
            }
            views.setImageViewResource(R.id.btn_play, playIcon)

            // Botones multimedia conectados a MediaButtonReceiver
            views.setOnClickPendingIntent(R.id.btn_prev, buildMediaButtonIntent(context, KeyEvent.KEYCODE_MEDIA_PREVIOUS))
            views.setOnClickPendingIntent(R.id.btn_play, buildMediaButtonIntent(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE))
            views.setOnClickPendingIntent(R.id.btn_next, buildMediaButtonIntent(context, KeyEvent.KEYCODE_MEDIA_NEXT))

            // Tocar el título abre la aplicación
            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (launchIntent != null) {
                val pendingLaunch = PendingIntent.getActivity(
                    context, 0, launchIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                views.setOnClickPendingIntent(R.id.widget_title, pendingLaunch)
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        private fun buildMediaButtonIntent(context: Context, keyCode: Int): PendingIntent {
            val intent = Intent(Intent.ACTION_MEDIA_BUTTON)
            intent.component = ComponentName(context, "com.ryanheise.audioservice.MediaButtonReceiver")
            val keyEvent = KeyEvent(KeyEvent.ACTION_DOWN, keyCode)
            intent.putExtra(Intent.EXTRA_KEY_EVENT, keyEvent)
            return PendingIntent.getBroadcast(
                context, keyCode, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }
    }
}
