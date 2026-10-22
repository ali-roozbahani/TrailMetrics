import Foundation

func removeBestEffort(path: String) {
    // swiftlint:disable:next optional_try - the file may already be gone and the user can't act on it
    try? FileManager.default.removeItem(atPath: path)
}

func readWithHandler(path: String) -> Data? {
    do {
        return try Data(contentsOf: URL(fileURLWithPath: path))
    } catch {
        return nil
    }
}
