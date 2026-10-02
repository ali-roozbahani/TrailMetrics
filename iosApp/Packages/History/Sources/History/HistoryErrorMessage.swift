//
//  HistoryErrorMessage.swift
//  History
//

/// The text History and Details show for a failed load or delete. Same wording as Route's
/// and Tracking's `RouteUiErrorGeneral`; persistence failures carry no `RouteError`
/// (`tm-kmp-shared`, "`@Throws` policy" rule 3), so there is nothing more specific to say.
enum HistoryErrorMessage {
    static let general = "Something went wrong. Please try again."
}
