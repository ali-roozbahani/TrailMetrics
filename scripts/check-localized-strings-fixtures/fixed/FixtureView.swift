import SwiftUI

struct FixtureView: View {
    @State private var showAlert = false
    @State private var weight = ""
    let message: String

    var body: some View {
        VStack {
            Text("Generate Route", bundle: .module)
            Text(
                "Multi-line literal",
                bundle: .module
            )
            Button {} label: { Text("Save", bundle: .module) }
            Label { Text("Reset", bundle: .module) } icon: { Image(systemName: "arrow.clockwise") }
            TextField(text: $weight) { Text("Weight (kg)", bundle: .module) }
            Text(message)
            Text(verbatim: "42")
            Image(systemName: "map")
        }
        .navigationTitle(Text("User Profile", bundle: .module))
        .alert(
            Text("Error", bundle: .module),
            isPresented: $showAlert
        ) {
            Button(role: .cancel) {} label: { Text("Cancel", bundle: .module) }
        }
    }
}
