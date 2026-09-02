package com.carelink.carelink_guardian

import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class FallAlertMessagingService : FirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        val event = message.data["event"]?.trim().orEmpty()
        val id = (message.data["eventId"] ?: message.messageId
            ?: "${event}_${System.currentTimeMillis()}").trim()
        if (event.isEmpty() || id.isEmpty() || wasAlreadyShown(id)) return

        when (event) {
            "fall_detected" -> {
                val cameraId = message.data["cameraId"]?.takeIf { it.isNotBlank() }
                    ?: "알 수 없는 위치"
                FallAlertNotifications.showFall(this, id, cameraId)
            }
            "meal_completed", "meal_complete" -> FallAlertNotifications.show(
                this, id, "식사 완료",
                message.data["message"]?.takeIf { it.isNotBlank() }
                    ?: "어르신이 식사를 완료했습니다.",
            )
            "guardian_call", "caregiver_call" -> FallAlertNotifications.show(
                this, id, "보호자 호출",
                message.data["message"]?.takeIf { it.isNotBlank() }
                    ?: "어르신이 보호자를 호출했습니다.",
            )
        }
    }

    private fun wasAlreadyShown(eventId: String): Boolean {
        val preferences = getSharedPreferences(PREFERENCES, MODE_PRIVATE)
        val ids = preferences.getStringSet(SHOWN_IDS, emptySet()).orEmpty().toMutableSet()
        if (!ids.add(eventId)) return true
        if (ids.size > MAX_IDS) ids.remove(ids.first())
        preferences.edit().putStringSet(SHOWN_IDS, ids).apply()
        return false
    }

    companion object {
        private const val PREFERENCES = "carelink_notifications"
        private const val SHOWN_IDS = "shown_event_ids"
        private const val MAX_IDS = 200
    }
}
