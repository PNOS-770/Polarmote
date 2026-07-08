package com.example.Polarmote

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

class SshForegroundService : Service() {
    companion object {
        private const val CHANNEL_ID = "Polarmote_ssh_foreground"
        private const val CHANNEL_NAME = "Polarmote SSH"
        private const val NOTIFICATION_ID = 7702
        private const val WAKE_LOCK_TAG = "Polarmote:ssh_foreground"
        private const val WIFI_LOCK_TAG = "Polarmote:ssh_wifi_foreground"
        private const val EXTRA_TITLE = "title"

        @Volatile
        var isRunning: Boolean = false
            private set

        @Volatile
        private var lastTitle: String = ""

        @Volatile
        private var lastActiveCount: Int = 0

        fun start(context: Context, title: String?) {
            val normalizedTitle = title?.trim().orEmpty()
            if (normalizedTitle.isNotEmpty()) {
                lastTitle = normalizedTitle
            }
            val intent =
                Intent(context, SshForegroundService::class.java).apply {
                    putExtra(EXTRA_TITLE, normalizedTitle)
                }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, SshForegroundService::class.java)
            context.stopService(intent)
        }

        fun updateState(
            context: Context,
            title: String?,
            activeCount: Int?,
        ) {
            val normalizedTitle = title?.trim().orEmpty()
            if (normalizedTitle.isNotEmpty()) {
                lastTitle = normalizedTitle
            }
            if (activeCount != null) {
                lastActiveCount = activeCount.coerceAtLeast(0)
            }
            if (!isRunning) {
                return
            }
            val manager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                    ?: return
            manager.notify(
                NOTIFICATION_ID,
                buildNotification(context),
            )
        }

        private fun buildNotification(context: Context): Notification {
            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            val contentIntent =
                launchIntent?.let {
                    PendingIntent.getActivity(
                        context,
                        0,
                        it,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                    )
                }
            val title = if (lastTitle.isBlank()) "Polarmote SSH" else lastTitle
            val itemCount = lastActiveCount.coerceAtLeast(0)
            val contentText =
                if (itemCount > 0) {
                    "SSH 会话后台保持中 · $itemCount 项"
                } else {
                    "SSH 会话后台保持中"
                }
            return NotificationCompat.Builder(context, CHANNEL_ID)
                .setContentTitle(title)
                .setContentText(contentText)
                .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setCategory(NotificationCompat.CATEGORY_SERVICE)
                .apply {
                    if (contentIntent != null) {
                        setContentIntent(contentIntent)
                    }
                }
                .build()
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onCreate() {
        super.onCreate()
        ensureNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra(EXTRA_TITLE)?.trim().orEmpty()
        if (title.isNotEmpty()) {
            lastTitle = title
        }
        startForeground(NOTIFICATION_ID, buildNotification(applicationContext))
        acquireWakeLock()
        acquireWifiLock()
        isRunning = true
        return START_STICKY
    }

    override fun onDestroy() {
        releaseWifiLock()
        releaseWakeLock()
        isRunning = false
        super.onDestroy()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        if (isRunning) {
            val restartIntent =
                Intent(applicationContext, SshForegroundService::class.java).apply {
                    putExtra(EXTRA_TITLE, lastTitle)
                }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    applicationContext.startForegroundService(restartIntent)
                } else {
                    applicationContext.startService(restartIntent)
                }
            } catch (_: Exception) {
                // Ignore restart failures.
            }
        }
        super.onTaskRemoved(rootIntent)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Keep SSH sessions alive while app is in background."
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun acquireWakeLock() {
        val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return
        if (wakeLock?.isHeld == true) {
            return
        }
        wakeLock =
            powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_LOCK_TAG).apply {
                setReferenceCounted(false)
                acquire()
            }
    }

    private fun acquireWifiLock() {
        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager ?: return
        if (wifiLock?.isHeld == true) {
            return
        }
        try {
            wifiLock =
                wifiManager.createWifiLock(
                    WifiManager.WIFI_MODE_FULL_HIGH_PERF,
                    WIFI_LOCK_TAG,
                ).apply {
                    setReferenceCounted(false)
                    acquire()
                }
        } catch (_: Exception) {
            // Ignore lock acquisition failures; wake lock + foreground service still helps.
        }
    }

    private fun releaseWakeLock() {
        val lock = wakeLock
        wakeLock = null
        if (lock?.isHeld == true) {
            lock.release()
        }
    }

    private fun releaseWifiLock() {
        val lock = wifiLock
        wifiLock = null
        if (lock?.isHeld == true) {
            lock.release()
        }
    }
}
