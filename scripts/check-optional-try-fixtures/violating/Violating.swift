import Foundation

func readBare(path: String) -> Data? {
    try? Data(contentsOf: URL(fileURLWithPath: path))
}

func readBound(path: String) -> Int {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return 0 }
    return data.count
}

func readAwait(loader: () async throws -> Int) async -> Int {
    let value = try? await loader()
    return value ?? 0
}
