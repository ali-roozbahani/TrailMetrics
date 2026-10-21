import SwiftUI

// A test helper and previews may use literals: the rules only cover production sources.
struct FixtureViewTests: View {
    var body: some View {
        VStack {
            Text("Generate Route")
            Button("Save") {}
        }
        .navigationTitle("User Profile")
    }
}
