package dev.roozbahani.trailmetrics.core.testing

import dev.roozbahani.trailmetrics.domain.util.Logger

/** Keeps every message passed to [debug] in [messages]. */
class FakeLogger : Logger {
    val messages = mutableListOf<String>()

    override fun debug(tag: String, message: String) {
        messages += message
    }
}
