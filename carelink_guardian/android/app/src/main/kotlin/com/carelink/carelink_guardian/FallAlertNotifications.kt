package com.carelink.carelink_guardian

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

object FallAlertNotifications {
    val TOPICS = listOf("fall-alerts", "meal-alerts", "guardian-calls")
    const val CHANNEL_ID = "fall_alerts"
    const val EXTRA_EVENT_ID = "fall_event_id"

    fun createChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "CareLink 알림", NotificationManager.IMPORTANCE_HIGH,
            ).apply { description = "낙상, 식사 완료 및 보호자 호출 알림" }
            context.getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }
    }

    fun showFall(context: Context, eventId: String, cameraId: String) = show(
        context, eventId, "낙상 감지", "$cameraId 카메라에서 낙상이 감지되었습니다.", eventId,
    )

    fun show(
        context: Context,
        notificationId: String,
        title: String,
        message: String,
        eventId: String? = null,
    ) {
        createChannel(context)
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            eventId?.let { putExtra(EXTRA_EVENT_ID, it) }
        }
        val pendingIntent = PendingIntent.getActivity(
            context, notificationId.hashCode(), intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_fall_notification)
            .setContentTitle(title)
            .setContentText(message)
            .setStyle(NotificationCompat.BigTextStyle().bigText(message))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()
        NotificationManagerCompat.from(context).notify(notificationId.hashCode(), notification)
    }
}
