//
//  HistoryErrorMessage.swift
//  History
//

import Foundation

/// The text History and Details show for a failed load or delete. Same wording as Route's
/// and Tracking's `RouteUiErrorGeneral`; persistence failures carry no `RouteError`
/// (`tm-kmp-shared`, "`@Throws` policy" rule 3), so there is nothing more specific to say.
enum HistoryErrorMessage {
    static var general: String {
        String(localized: "general_error_message", bundle: .module)
    }
}
