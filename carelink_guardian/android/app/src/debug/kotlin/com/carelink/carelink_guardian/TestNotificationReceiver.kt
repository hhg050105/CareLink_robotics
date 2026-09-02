package com.carelink.carelink_guardian

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class TestNotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val type = intent.getStringExtra("type")
        val (title, message) = when (type) {
            "guardian_call" -> "보호자 호출" to "어르신이 보호자를 호출했습니다."
            "fall_detected" -> "낙상 감지" to "거실 카메라에서 낙상이 감지되었습니다."
            else -> "식사 완료" to "어르신이 식사를 완료했습니다."
        }
        FallAlertNotifications.show(
            context = context,
            notificationId = "debug_${type}_${System.currentTimeMillis()}",
            title = "$title (테스트)",
            message = message,
        )
    }
}
