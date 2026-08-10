package com.example.ganci

import android.app.Notification
import android.content.ComponentName
import android.content.Context
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSession
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log

class MediaNotificationListener : NotificationListenerService() {

    companion object {
        @Volatile var cachedTitle: String = ""
        @Volatile var cachedArtist: String = ""
        @Volatile var cachedDurationMs: Long = 0L
        @Volatile var cachedPositionMs: Long = 0L
        @Volatile var cachedIsPlaying: Boolean = false
        @Volatile var cachedStateTimestamp: Long = 0L
        @Volatile var cachedThumbnail: String = ""
        @Volatile var activeController: MediaController? = null

        fun extractThumbnail(metadata: MediaMetadata?, context: Context): String {
            if (metadata == null) return ""
            try {
                var artwork = metadata.getBitmap(MediaMetadata.METADATA_KEY_ART)
                    ?: metadata.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART)
                    ?: metadata.getBitmap(MediaMetadata.METADATA_KEY_DISPLAY_ICON)
                if (artwork != null) {
                    var bmp = artwork
                    if (bmp.width > 350 || bmp.height > 350) {
                        bmp = android.graphics.Bitmap.createScaledBitmap(bmp, 280, 280, true)
                    }
                    val stream = java.io.ByteArrayOutputStream()
                    bmp.compress(android.graphics.Bitmap.CompressFormat.JPEG, 75, stream)
                    return android.util.Base64.encodeToString(stream.toByteArray(), android.util.Base64.NO_WRAP)
                } else {
                    val artUri = metadata.getString(MediaMetadata.METADATA_KEY_ART_URI)
                        ?: metadata.getString(MediaMetadata.METADATA_KEY_ALBUM_ART_URI)
                        ?: metadata.getString(MediaMetadata.METADATA_KEY_DISPLAY_ICON_URI)
                    if (!artUri.isNullOrEmpty()) {
                        if (artUri.startsWith("http://") || artUri.startsWith("https://")) {
                            return artUri
                        } else if (artUri.startsWith("content://") || artUri.startsWith("file://")) {
                            try {
                                val uri = android.net.Uri.parse(artUri)
                                val inStream = context.contentResolver.openInputStream(uri)
                                if (inStream != null) {
                                    var bmp = android.graphics.BitmapFactory.decodeStream(inStream)
                                    inStream.close()
                                    if (bmp != null) {
                                        if (bmp.width > 350 || bmp.height > 350) {
                                            bmp = android.graphics.Bitmap.createScaledBitmap(bmp, 280, 280, true)
                                        }
                                        val stream = java.io.ByteArrayOutputStream()
                                        bmp.compress(android.graphics.Bitmap.CompressFormat.JPEG, 75, stream)
                                        return android.util.Base64.encodeToString(stream.toByteArray(), android.util.Base64.NO_WRAP)
                                    }
                                }
                            } catch (e: Exception) {
                                Log.e("MediaNotification", "Failed decode artUri: $artUri", e)
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                Log.e("MediaNotification", "Error extracting thumbnail", e)
            }
            return ""
        }
    }

    private val controllerCallback = object : MediaController.Callback() {
        override fun onMetadataChanged(metadata: MediaMetadata?) {
            if (metadata != null) {
                cachedTitle = metadata.getString(MediaMetadata.METADATA_KEY_TITLE) ?: ""
                cachedArtist = metadata.getString(MediaMetadata.METADATA_KEY_ARTIST)
                    ?: metadata.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST) ?: ""
                val dur = metadata.getLong(MediaMetadata.METADATA_KEY_DURATION)
                Log.d("MediaNotification", "onMetadataChanged: ${cachedTitle} dur=${dur}ms")
                if (dur > 0) cachedDurationMs = dur
                val thumb = extractThumbnail(metadata, this@MediaNotificationListener)
                if (thumb.isNotEmpty()) cachedThumbnail = thumb
            }
        }

        override fun onPlaybackStateChanged(state: PlaybackState?) {
            if (state != null) {
                cachedIsPlaying = state.state == PlaybackState.STATE_PLAYING
                cachedPositionMs = state.position
                cachedStateTimestamp = System.nanoTime()
                Log.d("MediaNotification", "onPlaybackStateChanged: playing=${cachedIsPlaying} pos=${cachedPositionMs}ms")
            }
        }
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.d("MediaNotification", "NotificationListener connected")
        try {
            val mgr = getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
            val cn = ComponentName(this, MediaNotificationListener::class.java)
            val controllers = mgr.getActiveSessions(cn)
            if (controllers.isNotEmpty()) {
                attachController(controllers[0])
            }
        } catch (_: SecurityException) {
            Log.d("MediaNotification", "getActiveSessions permission denied -- will wait for notification")
        }

        try {
            val active = activeNotifications
            active?.forEach { sbn -> tryAttachFromNotification(sbn) }
        } catch (_: Exception) {}
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        unregisterCallback()
        activeController = null
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        sbn ?: return
        tryAttachFromNotification(sbn)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        sbn ?: return
        val token = getSessionToken(sbn) ?: return
        if (activeController?.sessionToken == token) {
            Log.d("MediaNotification", "Media notification removed, clearing controller")
            unregisterCallback()
            activeController = null
        }
    }

    private fun tryAttachFromNotification(sbn: StatusBarNotification) {
        val token = getSessionToken(sbn) ?: return
        if (activeController?.sessionToken == token) return
        Log.d("MediaNotification", "Media notification from ${sbn.packageName} -- attaching controller")
        try {
            val controller = MediaController(this, token)
            attachController(controller)
        } catch (e: Exception) {
            Log.e("MediaNotification", "Failed to attach controller: ${e.message}")
        }
    }

    @Suppress("DEPRECATION")
    private fun getSessionToken(sbn: StatusBarNotification): MediaSession.Token? {
        val extras = sbn.notification?.extras ?: return null
        return extras.getParcelable(Notification.EXTRA_MEDIA_SESSION)
    }

    private fun attachController(controller: MediaController) {
        unregisterCallback()
        activeController = controller
        controller.registerCallback(controllerCallback)

        val meta = controller.metadata
        val state = controller.playbackState

        if (meta != null) {
            cachedTitle = meta.getString(MediaMetadata.METADATA_KEY_TITLE) ?: ""
            cachedArtist = meta.getString(MediaMetadata.METADATA_KEY_ARTIST)
                ?: meta.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST) ?: ""
            val dur = meta.getLong(MediaMetadata.METADATA_KEY_DURATION)
            Log.d("MediaNotification", "Seeding cache: ${cachedTitle}, dur=${dur}ms")
            if (dur > 0) cachedDurationMs = dur
            val thumb = extractThumbnail(meta, this)
            if (thumb.isNotEmpty()) cachedThumbnail = thumb
        }
        if (state != null) {
            cachedIsPlaying = state.state == PlaybackState.STATE_PLAYING
            cachedPositionMs = state.position
            cachedStateTimestamp = System.nanoTime()
        }
    }

    private fun unregisterCallback() {
        try { activeController?.unregisterCallback(controllerCallback) } catch (_: Exception) {}
    }
}
