//
//  HistoryView.swift
//  History
//
//  Created by Ali Roozbahani on 09.09.26.
//

import SwiftUI

public struct HistoryView: View {
    @StateObject private var viewModel = HistoryViewModel()

    public init() {}

    public var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
            } else if viewModel.activities.isEmpty {
                Text("No activities yet")
            } else {
                List(viewModel.activities, id: \.self) { activity in
                    Text("\(activity)")
                }
            }
        }
        .task {
            await viewModel.observe()
        }
    }
}
