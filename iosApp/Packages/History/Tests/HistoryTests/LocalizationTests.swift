//
//  LocalizationTests.swift
//  HistoryTests
//

@testable import History
import TestSupport
import XCTest

final class LocalizationTests: XCTestCase {

    func test_catalog_resolvesDescriptiveAndEnglishTextKeysThroughPackageBundle() {
        LocalizationAssertions.assertResolves(
            key: "delete_activity_title", to: "Delete this activity?", in: .module)
        LocalizationAssertions.assertResolves(
            key: "No Activities yet", to: "No Activities yet", in: .module)
    }

    func test_stringLocalizedWithPackageBundle_returnsCatalogValue() {
        XCTAssertEqual(HistoryErrorMessage.general, "Something went wrong. Please try again.")
    }

    // Adding a language is a catalog-only change: next to the compiled `en.lproj` of the package bundle, a
    // test-only `de.lproj` makes the same key resolve to the German text, while `en.lproj` keeps the catalog's.
    func test_testOnlyGermanEntry_resolvesInGermanLprojOnly() throws {
        let copy = FileManager.default.temporaryDirectory
            .appendingPathComponent("History-\(UUID().uuidString).bundle")
        try FileManager.default.copyItem(at: Bundle.module.bundleURL, to: copy)
        addTeardownBlock { try FileManager.default.removeItem(at: copy) }
        let german = copy.appendingPathComponent("de.lproj")
        try FileManager.default.createDirectory(at: german, withIntermediateDirectories: true)
        try "\"ok_button\" = \"Test-nur-OK\";\n".write(
            to: german.appendingPathComponent("Localizable.strings"), atomically: true, encoding: .utf8)

        let germanBundle = try XCTUnwrap(Bundle(url: german))
        let englishBundle = try XCTUnwrap(Bundle(url: copy.appendingPathComponent("en.lproj")))
        XCTAssertEqual(germanBundle.localizedString(forKey: "ok_button", value: nil, table: nil), "Test-nur-OK")
        XCTAssertEqual(englishBundle.localizedString(forKey: "ok_button", value: nil, table: nil), "OK")
    }
}
