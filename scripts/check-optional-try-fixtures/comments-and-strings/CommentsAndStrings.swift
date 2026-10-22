import Foundation

// A line comment that mentions try? is not a use of it.
/* A block comment: try? */
/// A doc comment: `try?` drops the error.
func describeOptionalTry() -> [String] {
    let single = "try? in a string"
    let interpolated = "value: \(single.count) and try? again"
    let multiline = """
    try? in a multiline string
    """
    return [single, interpolated, multiline]
}
