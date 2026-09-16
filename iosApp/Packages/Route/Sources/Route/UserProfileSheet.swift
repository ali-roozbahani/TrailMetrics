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
                TextField("Weight (kg)", text: $weightInput)
                    .keyboardType(.decimalPad)
            }
            .navigationTitle("User Profile")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let weightKg {
                            onSave(weightKg)
                        }
                    }
                    .disabled(!isValid)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
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
