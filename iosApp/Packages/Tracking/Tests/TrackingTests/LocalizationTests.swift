//
//  LocalizationTests.swift
//  TrackingTests
//

@testable import Tracking
import TestSupport
import XCTest

final class LocalizationTests: XCTestCase {

    func test_catalog_resolvesKeysThroughPackageBundle() {
        LocalizationAssertions.assertResolves(key: "Route completed!", to: "Route completed!", in: .module)
        LocalizationAssertions.assertResolves(
            key: "general_error_message", to: "Something went wrong. Please try again.", in: .module)
    }
}
