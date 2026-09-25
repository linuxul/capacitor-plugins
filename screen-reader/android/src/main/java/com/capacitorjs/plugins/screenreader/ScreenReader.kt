package com.capacitorjs.plugins.screenreader

import android.content.Context
import android.media.AudioAttributes
import android.speech.tts.TextToSpeech
import android.view.accessibility.AccessibilityManager
import com.getcapacitor.Logger
import java.util.Locale

public class ScreenReader internal constructor(private val context: Context) {
    private val accessibilityManager = context.getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
    private val stateChangeListeners = ArrayList<AccessibilityManager.TouchExplorationStateChangeListener>()

    // One engine for every utterance, released by shutdown. speak and shutdown are called on the main thread, where
    // the engine also reports that it is ready, so none of this needs a lock.
    private var textToSpeech: TextToSpeech? = null
    private var isSpeechReady = false
    private var speechInitFailed = false
    private var pendingUtterance: Utterance? = null
    private var isShutDown = false

    private class Utterance(val text: String?, val locale: Locale)

    public fun interface ScreenReaderStateChangeListener {
        public fun onScreenReaderStateChanged(enabled: Boolean)
    }

    public val isEnabled: Boolean
        get() = accessibilityManager.isTouchExplorationEnabled

    public fun addStateChangeListener(listener: ScreenReaderStateChangeListener) {
        // The registered object is kept because the accessibility manager removes listeners by identity
        val registered = AccessibilityManager.TouchExplorationStateChangeListener(listener::onScreenReaderStateChanged)
        stateChangeListeners.add(registered)
        accessibilityManager.addTouchExplorationStateChangeListener(registered)
    }

    public fun removeAllListeners() {
        for (listener in stateChangeListeners) {
            accessibilityManager.removeTouchExplorationStateChangeListener(listener)
        }
        stateChangeListeners.clear()
    }

    /**
     * Speaks [text] when a screen reader is on. Call it on the main thread.
     */
    @JvmOverloads
    public fun speak(text: String?, languageTag: String = "en") {
        if (isShutDown || !isEnabled) {
            return
        }
        val utterance = Utterance(text, Locale.forLanguageTag(languageTag))
        val engine = textToSpeech
        if (engine != null && isSpeechReady) {
            say(engine, utterance)
            return
        }

        // Spoken once the engine is ready. A later utterance replaces it, as QUEUE_FLUSH would.
        pendingUtterance = utterance
        if (engine == null) {
            speechInitFailed = false
            val started = TextToSpeech(context, ::onSpeechInit)
            if (speechInitFailed) {
                // No engine could be bound, and the constructor has reported that already
                started.shutdown()
            } else {
                textToSpeech = started
            }
        }
    }

    /**
     * Releases the text-to-speech engine. Call it on the main thread when the plugin is destroyed.
     */
    public fun shutdown() {
        isShutDown = true
        textToSpeech?.shutdown()
        textToSpeech = null
        isSpeechReady = false
        pendingUtterance = null
    }

    private fun onSpeechInit(status: Int) {
        if (status != TextToSpeech.SUCCESS) {
            Logger.error("Unable to start text-to-speech, status $status")
            speechInitFailed = true
            pendingUtterance = null
            // The next utterance tries again
            textToSpeech?.shutdown()
            textToSpeech = null
            return
        }
        // Null when shutdown came first
        val engine = textToSpeech ?: return
        engine.setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ASSISTANCE_ACCESSIBILITY).build())
        isSpeechReady = true
        pendingUtterance?.let { say(engine, it) }
        pendingUtterance = null
    }

    private fun say(engine: TextToSpeech, utterance: Utterance) {
        engine.setLanguage(utterance.locale)
        engine.speak(utterance.text, TextToSpeech.QUEUE_FLUSH, null, "capacitor-screen-reader" + System.currentTimeMillis())
    }
}
