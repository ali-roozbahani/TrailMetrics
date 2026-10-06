# Sample skill

The flow emits a failure value and
then completes; `invoke()` itself never throws. iOS `HistoryViewModel` consumes that; Android
still uses the repository Flow.
