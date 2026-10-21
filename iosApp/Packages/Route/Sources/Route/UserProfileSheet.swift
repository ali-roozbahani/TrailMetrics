//
//  UserProfileSheet.swift
//  Route
//

import SwiftUI

struct UserProfileSheet: View {
    let initialWeightKg: Double?
    let onSave: (Double) -> Void
    let onDismiss: () -> Void

    @State private var weightInput = ""

    private var weightKg: Double? { Double(weightInput) }
    private var isValid: Bool { (weightKg ?? 0) > 0 }

    var body: some View {
        NavigationStack {
            Form {
                TextField(text: $weightInput) { Text("Weight (kg)", bundle: .module) }
                    .keyboardType(.decimalPad)
            }
            .navigationTitle(Text("User Profile", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        if let weightKg {
                            onSave(weightKg)
                        }
                    } label: {
                        Text("Save", bundle: .module)
                    }
                    .disabled(!isValid)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onDismiss) { Text("Cancel", bundle: .module) }
                }
            }
        }
        .onChange(of: initialWeightKg, initial: true) { _, newValue in
            if weightInput.isEmpty, let newValue {
                weightInput = String(newValue)
            }
        }
    }
}
