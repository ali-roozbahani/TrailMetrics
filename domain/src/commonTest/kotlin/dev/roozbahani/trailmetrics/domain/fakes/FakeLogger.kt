package dev.roozbahani.trailmetrics.domain.fakes

import dev.roozbahani.trailmetrics.domain.util.Logger

class FakeLogger : Logger {
    val loggedMessages = mutableListOf<Pair<String, String>>()

    override fun debug(tag: String, message: String) {
        loggedMessages += tag to message
    }
}
