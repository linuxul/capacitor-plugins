package com.capacitorjs.plugins.screenreader

import android.content.Context
import android.media.AudioAttributes
import android.speech.tts.TextToSpeech
import android.view.accessibility.AccessibilityManager
import java.util.Locale

public class ScreenReader internal constructor(private val context: Context) {
    private val accessibilityManager = context.getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
    private val stateChangeListeners = ArrayList<AccessibilityManager.TouchExplorationStateChangeListener>()
    private var textToSpeech: TextToSpeech? = null

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
    }

    @JvmOverloads
    public fun speak(text: String?, languageTag: String = "en") {
        if (isEnabled) {
            val locale = Locale.forLanguageTag(languageTag)

            textToSpeech =
                TextToSpeech(context) {
                    val attributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ASSISTANCE_ACCESSIBILITY).build()
                    textToSpeech?.run {
                        setAudioAttributes(attributes)
                        setLanguage(locale)
                        speak(text, TextToSpeech.QUEUE_FLUSH, null, "capacitor-screen-reader" + System.currentTimeMillis())
                    }
                }
        }
    }
}
