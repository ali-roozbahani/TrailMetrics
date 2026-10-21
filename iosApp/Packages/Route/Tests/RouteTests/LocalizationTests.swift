//
//  LocalizationTests.swift
//  RouteTests
//

@testable import Route
import TestSupport
import XCTest

final class LocalizationTests: XCTestCase {

    func test_catalog_resolvesKeysThroughPackageBundle() {
        LocalizationAssertions.assertResolves(
            key: "map_unavailable_message",
            to: "The map is unavailable because the Google Maps key is not configured. "
                + "Set the key in the build settings.",
            in: .module
        )
        LocalizationAssertions.assertResolves(key: "Generate Route", to: "Generate Route", in: .module)
    }
}
