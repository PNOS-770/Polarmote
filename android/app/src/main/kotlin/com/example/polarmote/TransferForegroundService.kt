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

class TransferForegroundService : Service() {
    companion object {
        private const val CHANNEL_ID = "Polarmote_transfer_foreground"
        private const val CHANNEL_NAME = "Polarmote Transfer"
        private const val NOTIFICATION_ID = 7701
        private const val WAKE_LOCK_TAG = "Polarmote:transfer_foreground"
        private const val WIFI_LOCK_TAG = "Polarmote:transfer_wifi_foreground"
        private const val EXTRA_TITLE = "title"

        @Volatile
        var isRunning: Boolean = false
            private set

        @Volatile
        private var lastTitle: String = ""

        @Volatile
        private var lastProgressPermille: Int = 0

        @Volatile
        private var lastIndeterminate: Boolean = true

        @Volatile
        private var lastActiveCount: Int = 0

        fun start(context: Context, title: String?) {
            val normalizedTitle = title?.trim().orEmpty()
            if (normalizedTitle.isNotEmpty()) {
                lastTitle = normalizedTitle
            }
            val intent =
                Intent(context, TransferForegroundService::class.java).apply {
                    putExtra(EXTRA_TITLE, normalizedTitle)
                }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, TransferForegroundService::class.java)
            context.stopService(intent)
        }

        fun updateProgress(
            context: Context,
            title: String?,
            progressPermille: Int?,
            progressPercent: Int?,
            indeterminate: Boolean?,
            activeCount: Int?,
        ) {
            val normalizedTitle = title?.trim().orEmpty()
            if (normalizedTitle.isNotEmpty()) {
                lastTitle = normalizedTitle
            }
            if (progressPermille != null) {
                lastProgressPermille = progressPermille.coerceIn(0, 1000)
            } else if (progressPercent != null) {
                lastProgressPermille = (progressPercent.coerceIn(0, 100) * 10)
            }
            if (indeterminate != null) {
                lastIndeterminate = indeterminate
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
            val title = if (lastTitle.isBlank()) "Polarmote" else lastTitle
            val itemCount = lastActiveCount.coerceAtLeast(0)
            val contentText =
                if (lastIndeterminate) {
                    if (itemCount > 0) "传输中 · $itemCount 项" else "文件传输进行中"
                } else {
                    val percentText = formatPercentFromPermille(lastProgressPermille)
                    if (itemCount > 0) {
                        "传输中 · $itemCount 项 · ${percentText}%"
                    } else {
                        "传输进度 ${percentText}%"
                    }
                }
            return NotificationCompat.Builder(context, CHANNEL_ID)
                .setContentTitle(title)
                .setContentText(contentText)
                .setSmallIcon(android.R.drawable.stat_sys_upload)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setCategory(NotificationCompat.CATEGORY_SERVICE)
                .setProgress(
                    1000,
                    lastProgressPermille.coerceIn(0, 1000),
                    lastIndeterminate,
                )
                .apply {
                    if (contentIntent != null) {
                        setContentIntent(contentIntent)
                    }
                }
                .build()
        }

        private fun formatPercentFromPermille(permille: Int): String {
            val bounded = permille.coerceIn(0, 1000)
            val integerPart = bounded / 10
            val decimalPart = bounded % 10
            return if (decimalPart == 0) {
                "$integerPart"
            } else {
                "$integerPart.$decimalPart"
            }
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
                Intent(applicationContext, TransferForegroundService::class.java).apply {
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
            description = "Keep transfer tasks alive while app is in background."
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
