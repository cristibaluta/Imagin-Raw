//
//  CopyToView.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 10.02.2026.
//

import SwiftUI

// MARK: - Container

struct CopyToView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: PhotoCopySheetModel

    var body: some View {
        Group {
            if viewModel.isCopying {
                CopyProgressView(viewModel: viewModel) {
                    dismiss()
                }
                .padding(20)
                .frame(minWidth: 500, minHeight: 180)
            } else {
                CopyOptionsView(viewModel: viewModel) {
                    viewModel.saveSettings()
                    Task(priority: .userInitiated) {
                        await viewModel.startCopy()
                        if viewModel.copyError == nil && !viewModel.isCancelled {
                            try? await Task.sleep(nanoseconds: 500_000_000)
                            dismiss()
                        }
                    }
                } onCancel: {
                    dismiss()
                }
                .frame(minWidth: 500, minHeight: 420)
            }
        }
//        .onDisappear {
//            viewModel.stopAccessingSecurityScopedResources()
//        }
    }
}
