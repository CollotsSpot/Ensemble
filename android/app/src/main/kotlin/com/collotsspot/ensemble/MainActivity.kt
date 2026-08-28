package com.collotsspot.ensemble

import android.content.Context
import android.database.ContentObserver
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.view.KeyEvent
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Extend AudioServiceActivity instead of FlutterActivity to support audio_service package
// while also intercepting volume button events
class MainActivity: AudioServiceActivity() {
    private val TAG = "EnsembleVolume"
    private val CHANNEL = "com.collotsspot.ensemble/volume_buttons"
    private var methodChannel: MethodChannel? = null
    private var isListening = false
    // Set to true when MA is actively playing (sent from Flutter).
    // Used by the volume observer to suppress volume mirroring when MA is not streaming.
    private var isMAPlaying = false

    // Volume observer for lockscreen volume changes
    // Watches system STREAM_MUSIC volume and mirrors changes to the MA player
    // when a remote/group player is active
    private var audioManager: AudioManager? = null
    private var volumeObserver: VolumeContentObserver? = null
    private var isObservingVolume = false
    private var lastKnownVolume: Int = -1
    // Guard flag to ignore volume changes triggered by our own setStreamVolume calls
    private var ignoringVolumeChange = false
    // Tracks the estimated MA volume locally so the system slider can shadow
    // the MA position without a Flutter round-trip.  Updated in lockstep with
    // every observer event and reset by syncSystemVolume / startVolumeObserver.
    private var estimatedMAVolume = 50

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.d(TAG, "Configuring Flutter engine, setting up MethodChannel")

        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            Log.d(TAG, "Received method call: ${call.method}")
            when (call.method) {
                "startListening" -> {
                    isListening = true
                    Log.d(TAG, "Volume listening ENABLED")
                    result.success(null)
                }
                "stopListening" -> {
                    isListening = false
                    Log.d(TAG, "Volume listening DISABLED")
                    result.success(null)
                }
                "startVolumeObserver" -> {
                    // Start observing system volume for lockscreen volume changes.
                    // Optional: initialVolume (0-100) sets the system volume to match
                    // the MA player's current volume for a consistent HUD display.
                    val initialVolume = call.argument<Int>("initialVolume")
                    startVolumeObserver(initialVolume)
                    result.success(null)
                }
                "stopVolumeObserver" -> {
                    stopVolumeObserver()
                    result.success(null)
                }
                "syncSystemVolume" -> {
                    // Sync system volume to match MA player volume (0-100)
                    val volume = call.argument<Int>("volume") ?: 0
                    syncSystemVolume(volume)
                    result.success(null)
                }
                "setMAPlayingState" -> {
                    // Flutter notifies us whether MA is actively playing.
                    // The volume observer uses this to suppress mirroring when
                    // MA is paused, idle, or stopped.
                    isMAPlaying = call.argument<Boolean>("isPlaying") ?: false
                    Log.d(TAG, "MA playing state updated: isMAPlaying=$isMAPlaying")
                    result.success(null)
                }
                else -> {
                    Log.d(TAG, "Unknown method: ${call.method}")
                    result.notImplemented()
                }
            }
        }
    }

    /// Start observing system STREAM_MUSIC volume changes.
    /// When a change is detected, sends an "absoluteVolumeChange" event to Flutter
    /// with the new volume mapped to 0-100 scale.
    private fun startVolumeObserver(initialVolume: Int?) {
        if (isObservingVolume) return

        val am = audioManager ?: return

        // Optionally set system volume to match the MA player's current volume
        if (initialVolume != null) {
            estimatedMAVolume = initialVolume
            syncSystemVolume(initialVolume)
        }

        lastKnownVolume = am.getStreamVolume(AudioManager.STREAM_MUSIC)

        volumeObserver = VolumeContentObserver(Handler(Looper.getMainLooper()))
        contentResolver.registerContentObserver(
            Settings.System.CONTENT_URI,
            true,
            volumeObserver!!
        )
        isObservingVolume = true
        Log.d(TAG, "Volume observer STARTED, initial system volume: $lastKnownVolume")
    }

    /// Stop observing system volume changes.
    private fun stopVolumeObserver() {
        if (!isObservingVolume) return

        volumeObserver?.let {
            contentResolver.unregisterContentObserver(it)
        }
        volumeObserver = null
        isObservingVolume = false
        Log.d(TAG, "Volume observer STOPPED")
    }

    /// Set the system STREAM_MUSIC volume to match an MA player volume (0-100).
    /// Maps MA's 0-100 range to the device's 0-maxVolume range.
    private fun syncSystemVolume(maVolume: Int) {
        val am = audioManager ?: return
        val maxSystemVolume = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        val systemVolume = (maVolume * maxSystemVolume / 100).coerceIn(0, maxSystemVolume)

        estimatedMAVolume = maVolume

        ignoringVolumeChange = true
        am.setStreamVolume(AudioManager.STREAM_MUSIC, systemVolume, 0)
        lastKnownVolume = systemVolume
        // Clear the guard after a short delay so the ContentObserver's echo
        // (dispatched asynchronously via Handler) is still suppressed.
        // 100ms is plenty — the echo arrives within one main-thread frame (~16ms).
        Handler(Looper.getMainLooper()).postDelayed({ ignoringVolumeChange = false }, 100)
        Log.d(TAG, "Synced system volume: MA $maVolume% -> system $systemVolume/$maxSystemVolume")
    }

    /// ContentObserver that watches for system volume changes.
    /// When volume changes (e.g., from lockscreen hardware buttons),
    /// maps the change to a 0-100 value and sends to Flutter along with
    /// the button direction (+1 up, -1 down).
    inner class VolumeContentObserver(handler: Handler) : ContentObserver(handler) {
        override fun onChange(selfChange: Boolean) {
            super.onChange(selfChange)

            val am = audioManager ?: return
            val currentVolume = am.getStreamVolume(AudioManager.STREAM_MUSIC)

            // Always track the real system volume BEFORE checking guards.
            // This ensures direction detection is accurate even after periods
            // where events were suppressed (e.g., MA was paused, or during
            // the ignoringVolumeChange window after syncSystemVolume).
            val previousVolume = lastKnownVolume
            lastKnownVolume = currentVolume

            // Guards: suppress the event but volume tracking above stays accurate.
            if (ignoringVolumeChange) return
            if (!isMAPlaying) return
            if (am.isMusicActive) return
            if (am.mode != AudioManager.MODE_NORMAL) return

            if (currentVolume != previousVolume) {
                val maxVolume = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                val maVolume = if (maxVolume > 0) (currentVolume * 100 / maxVolume) else 0
                val prevMaVolume = if (maxVolume > 0) (previousVolume * 100 / maxVolume) else 0
                val direction = if (currentVolume > previousVolume) 1 else -1
                // Per-step delta mapped to 0-100 scale so Flutter can match
                // the system volume rate of change exactly.
                val delta = Math.abs(maVolume - prevMaVolume)

                Log.d(TAG, "Volume observer: system $previousVolume -> $currentVolume (MA: $maVolume%, delta: $delta, dir: $direction)")

                // Update local MA estimate so the system slider can shadow it.
                estimatedMAVolume = (estimatedMAVolume + direction * delta).coerceIn(0, 100)

                // Send volume + direction + delta to Flutter
                methodChannel?.invokeMethod("absoluteVolumeChange", mapOf("volume" to maVolume, "direction" to direction, "delta" to delta))

                // Reset system volume to the position matching our estimated MA
                // volume, clamped to [1, max-1] so the ContentObserver always
                // has room to detect the next press in either direction.
                // This makes the system slider visually shadow the MA volume
                // instead of snapping to midpoint.
                val targetSystemVol = (estimatedMAVolume * maxVolume / 100).coerceIn(1, maxVolume - 1)
                if (currentVolume != targetSystemVol) {
                    ignoringVolumeChange = true
                    am.setStreamVolume(AudioManager.STREAM_MUSIC, targetSystemVol, 0)
                    lastKnownVolume = targetSystemVol
                    Handler(Looper.getMainLooper()).postDelayed({ ignoringVolumeChange = false }, 100)
                }
            }
        }
    }

    // Use dispatchKeyEvent instead of onKeyDown - Flutter's engine uses dispatchKeyEvent
    // and may consume events before they reach onKeyDown
    override fun dispatchKeyEvent(event: KeyEvent?): Boolean {
        if (event == null) {
            return super.dispatchKeyEvent(event)
        }

        val keyCode = event.keyCode
        val action = event.action

        Log.d(TAG, "dispatchKeyEvent: keyCode=$keyCode, action=$action, isListening=$isListening")

        // Only handle KEY_DOWN events to avoid double-triggering (down + up)
        if (action != KeyEvent.ACTION_DOWN) {
            // For volume keys when listening, also consume ACTION_UP to fully block system volume
            if (isListening && (keyCode == KeyEvent.KEYCODE_VOLUME_UP || keyCode == KeyEvent.KEYCODE_VOLUME_DOWN)) {
                Log.d(TAG, "Consuming ACTION_UP for volume key")
                return true
            }
            return super.dispatchKeyEvent(event)
        }

        if (!isListening) {
            Log.d(TAG, "Not listening, passing to super")
            return super.dispatchKeyEvent(event)
        }

        return when (keyCode) {
            KeyEvent.KEYCODE_VOLUME_UP -> {
                Log.d(TAG, "VOLUME UP pressed - sending to Flutter")
                methodChannel?.invokeMethod("volumeUp", null)
                true // Consume the event to prevent system volume change
            }
            KeyEvent.KEYCODE_VOLUME_DOWN -> {
                Log.d(TAG, "VOLUME DOWN pressed - sending to Flutter")
                methodChannel?.invokeMethod("volumeDown", null)
                true // Consume the event to prevent system volume change
            }
            else -> {
                Log.d(TAG, "Other key, passing to super")
                super.dispatchKeyEvent(event)
            }
        }
    }

    // Pause foreground key interception (dispatchKeyEvent) when the app goes to background
    // so hardware volume buttons don't intercept YouTube, ringer, etc.
    // The volume observer is intentionally kept alive across pause/resume — it is the
    // mechanism that routes lockscreen hardware-button presses to the MA player, and
    // it already guards against unwanted mirroring via isMAPlaying / isMusicActive / mode.
    private var wasListeningBeforePause = false

    override fun onPause() {
        wasListeningBeforePause = isListening
        isListening = false
        Log.d(TAG, "onPause: suspended key interception (wasListening=$wasListeningBeforePause), volume observer remains active")
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        if (wasListeningBeforePause) {
            isListening = true
        }
        Log.d(TAG, "onResume: restored key interception (listening=$isListening)")
    }

    override fun onDestroy() {
        stopVolumeObserver()
        super.onDestroy()
    }
}
