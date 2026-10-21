//
//  LocalizationAssertions.swift
//  TestSupport
//

import Foundation
import XCTest

/// Proves that a feature package's own string catalog is packaged and found through its bundle
/// (`Bundle.module`), which is where every user-visible text of the package must be looked up.
/// The sentinel makes the check fail when the key is missing, instead of passing on the key
/// that Foundation returns for an unknown one.
public enum LocalizationAssertions {
    private static let missing = "<<missing localization>>"

    public static func assertResolves(
        key: String,
        to expected: String,
        in bundle: Bundle,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            bundle.localizedString(forKey: key, value: missing, table: nil),
            expected,
            "'\(key)' does not resolve through the package bundle",
            file: file,
            line: line
        )
        // The same lookup against the main bundle (what a text without `bundle: .module` does)
        // must miss: this is why the package bundle has to be passed.
        XCTAssertEqual(
            Bundle.main.localizedString(forKey: key, value: missing, table: nil),
            missing,
            "'\(key)' resolves through the main bundle: the test would not prove the package bundle",
            file: file,
            line: line
        )
    }
}
