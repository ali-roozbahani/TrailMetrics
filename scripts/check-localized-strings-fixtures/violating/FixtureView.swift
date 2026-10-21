import SwiftUI

struct FixtureView: View {
    @State private var showAlert = false
    @State private var weight = ""

    var body: some View {
        VStack {
            Text("Generate Route")
            Text(
                "Multi-line literal"
            )
            Button("Save") {}
            Label("Reset", systemImage: "arrow.clockwise")
            TextField("Weight (kg)", text: $weight)
        }
        .navigationTitle("User Profile")
        .alert(
            "Error",
            isPresented: $showAlert
        ) {
            Button(role: .cancel) {} label: { Text("Cancel", bundle: .module) }
        }
    }
}
