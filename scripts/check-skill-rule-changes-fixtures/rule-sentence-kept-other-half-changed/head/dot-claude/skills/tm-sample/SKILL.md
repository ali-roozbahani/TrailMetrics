# Sample skill

The flow emits a failure value and
then completes; `invoke()` itself never throws. The iOS and Android `HistoryViewModel`s both
consume that.
