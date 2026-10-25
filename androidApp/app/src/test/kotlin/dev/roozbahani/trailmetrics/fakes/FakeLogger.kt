package dev.roozbahani.trailmetrics.fakes

import dev.roozbahani.trailmetrics.domain.util.Logger

/** Keeps every message passed to [debug]. */
class FakeLogger : Logger {
    val messages = mutableListOf<String>()

    override fun debug(tag: String, message: String) {
        messages += message
    }
}
