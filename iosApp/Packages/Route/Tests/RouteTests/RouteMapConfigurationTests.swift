//
//  RouteMapConfigurationTests.swift
//  RouteTests
//

import Route
import XCTest

final class RouteMapConfigurationTests: XCTestCase {

    func test_apiKey_returnsTheKeyWhenPresent() {
        XCTAssertEqual(RouteMapConfiguration.apiKey(from: "abc123"), "abc123")
    }

    func test_apiKey_isNilForAnEmptyKey() {
        XCTAssertNil(RouteMapConfiguration.apiKey(from: ""))
    }

    func test_apiKey_isNilForAWhitespaceOnlyKey() {
        XCTAssertNil(RouteMapConfiguration.apiKey(from: "  \n"))
    }

    func test_apiKey_isNilWhenTheValueIsMissingOrNotAString() {
        XCTAssertNil(RouteMapConfiguration.apiKey(from: nil))
        XCTAssertNil(RouteMapConfiguration.apiKey(from: 42))
    }
}
