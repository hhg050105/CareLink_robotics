package com.carelink.carelink_guardian

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        FallAlertNotifications.createChannel(this)
        subscribeToAlertTopics()

        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            FALL_ALERT_CHANNEL,
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialEventId" -> result.success(consumeEventId(intent))
                    "subscribeToFallAlerts" -> {
                        val subscriptions = FallAlertNotifications.TOPICS.map {
                            FirebaseMessaging.getInstance().subscribeToTopic(it)
                        }
                        com.google.android.gms.tasks.Tasks.whenAll(subscriptions)
                            .addOnCompleteListener { task ->
                                if (task.isSuccessful) result.success(null)
                                else result.error("topic-subscription-failed", task.exception?.message, null)
                            }
                    }
                    "requestNotificationPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
                        ) {
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        consumeEventId(intent)?.let { channel?.invokeMethod("openFallEvent", it) }
    }

    private fun consumeEventId(source: Intent?): String? {
        val eventId = source?.getStringExtra(FallAlertNotifications.EXTRA_EVENT_ID)
        source?.removeExtra(FallAlertNotifications.EXTRA_EVENT_ID)
        return eventId
    }

    private fun subscribeToAlertTopics() {
        FallAlertNotifications.TOPICS.forEach {
            FirebaseMessaging.getInstance().subscribeToTopic(it)
        }
    }

    companion object {
        private const val FALL_ALERT_CHANNEL = "carelink/fall_alerts"
    }
}
