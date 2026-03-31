package com.example.ganci

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.media.MediaMetadata
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Build
import android.provider.Settings
import android.util.Base64
import android.graphics.Bitmap
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import androidx.core.app.ActivityCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import android.util.Log

class MainActivity : FlutterActivity() {
	private val MEDIA_CHANNEL = "flutter_media_controller"
	private val PERMISSION_CHANNEL = "media_permission_check"
	private val PERMISSION_REQUEST_CODE = 1001

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PERMISSION_CHANNEL)
			.setMethodCallHandler { call, result ->
				if (call.method == "isNotificationListenerEnabled") {
					result.success(isNotificationListenerEnabled())
				} else {
					result.notImplemented()
				}
			}

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_CHANNEL)
			.setMethodCallHandler { call, result ->
				when (call.method) {
					"requestPermissions" -> {
						requestMediaPermissions()
						result.success(true)
					}
					"getMediaInfo" -> {
						try {
							result.success(getCurrentMediaInfo())
						} catch (e: Exception) {
							result.error("MEDIA_ERROR", "Failed to get media info", e.message)
						}
					}
					"mediaAction" -> {
						val action = call.argument<String>("action")
						if (action != null) {
							handleMediaAction(action)
							result.success(null)
						} else {
							result.error("INVALID_ARGUMENT", "Action cannot be null", null)
						}
					}
					"seekTo" -> {
						val positionMs = call.argument<Int>("position")?.toLong() ?: call.argument<Long>("position")
						if (positionMs != null) {
							handleSeekTo(positionMs)
							result.success(null)
						} else {
							result.error("INVALID_ARGUMENT", "Position cannot be null", null)
						}
					}
					else -> result.notImplemented()
				}
			}
	}

	private fun isNotificationListenerEnabled(): Boolean {
		val enabled = Settings.Secure.getString(contentResolver, "enabled_notification_listeners") ?: return false
		return enabled.contains("$packageName/")
	}

	private fun requestMediaPermissions() {
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
			if (ContextCompat.checkSelfPermission(this, android.Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
				ActivityCompat.requestPermissions(this, arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), PERMISSION_REQUEST_CODE)
			}
		}
		startActivity(Intent(android.provider.Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
	}

	private fun getCurrentMediaInfo(): Map<String, Any> {
		return try {
			val mediaSessionManager = getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
			val componentName = ComponentName(this, MediaNotificationListener::class.java)

			val controllers = mediaSessionManager.getActiveSessions(componentName)
			if (controllers.isNotEmpty()) {
				val controller = controllers[0]
				val metadata = controller.metadata
				val playbackState = controller.playbackState

				var thumbnailBase64 = ""
				metadata?.let {
					val artwork = it.getBitmap(MediaMetadata.METADATA_KEY_ART) ?: it.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART)
					if (artwork != null) {
						val byteArrayOutputStream = ByteArrayOutputStream()
						artwork.compress(Bitmap.CompressFormat.PNG, 100, byteArrayOutputStream)
						val byteArray = byteArrayOutputStream.toByteArray()
						thumbnailBase64 = Base64.encodeToString(byteArray, Base64.DEFAULT)
					}
				}

				var currentPositionMs = playbackState?.position ?: 0L
				if (playbackState?.state == PlaybackState.STATE_PLAYING) {
					val timeDelta = android.os.SystemClock.elapsedRealtime() - (playbackState?.lastPositionUpdateTime ?: android.os.SystemClock.elapsedRealtime())
					val speed = playbackState?.playbackSpeed ?: 1.0f
					currentPositionMs += (timeDelta * speed).toLong()
				}

				mapOf(
					"track" to (metadata?.getString(MediaMetadata.METADATA_KEY_TITLE) ?: "Unknown Track"),
					"artist" to (metadata?.getString(MediaMetadata.METADATA_KEY_ARTIST) ?: "Unknown Artist"),
					"thumbnailUrl" to thumbnailBase64,
					"isPlaying" to (playbackState?.state == PlaybackState.STATE_PLAYING),
					"positionMs" to currentPositionMs,
					"durationMs" to (metadata?.getLong(MediaMetadata.METADATA_KEY_DURATION) ?: 0L)
				)
			} else {
				mapOf(
					"track" to "No track playing",
					"artist" to "Unknown artist",
					"thumbnailUrl" to "",
					"isPlaying" to false
				)
			}
		} catch (e: SecurityException) {
			Log.e("MainActivity", "SecurityException getting media info. Assuming permission missing.")
			mapOf(
				"track" to "No permission",
				"artist" to "Needs permission",
				"thumbnailUrl" to "",
				"isPlaying" to false
			)
		}
	}

	private fun handleMediaAction(action: String) {
		try {
			val mediaSessionManager = getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
			val componentName = ComponentName(this, MediaNotificationListener::class.java)

			val controllers = mediaSessionManager.getActiveSessions(componentName)
			if (controllers.isNotEmpty()) {
				val mediaController = controllers[0]
				when (action) {
					"previous" -> mediaController.transportControls.skipToPrevious()
					"playPause" -> {
						if (mediaController.playbackState?.state == PlaybackState.STATE_PLAYING) {
							mediaController.transportControls.pause()
						} else {
							mediaController.transportControls.play()
						}
					}
					"next" -> mediaController.transportControls.skipToNext()
				}
			}
		} catch (e: SecurityException) {
			Log.e("MainActivity", "SecurityException during media action")
		}
	}

	private fun handleSeekTo(positionMs: Long) {
		try {
			val mediaSessionManager = getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
			val componentName = ComponentName(this, MediaNotificationListener::class.java)

			val controllers = mediaSessionManager.getActiveSessions(componentName)
			if (controllers.isNotEmpty()) {
				val mediaController = controllers[0]
				mediaController.transportControls.seekTo(positionMs)
			}
		} catch (e: SecurityException) {
			Log.e("MainActivity", "SecurityException during seek to")
		}
	}
}
