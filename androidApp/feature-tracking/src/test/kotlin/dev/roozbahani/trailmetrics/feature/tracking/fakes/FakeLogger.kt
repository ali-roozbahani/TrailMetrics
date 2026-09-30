package dev.roozbahani.trailmetrics.feature.tracking.fakes

import dev.roozbahani.trailmetrics.domain.util.Logger

class FakeLogger : Logger {
    override fun debug(tag: String, message: String) = Unit
}
