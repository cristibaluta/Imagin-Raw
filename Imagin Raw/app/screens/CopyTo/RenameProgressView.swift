//
//  RenameProgressView.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 12.06.2026.
//

import SwiftUI

struct RenameProgressView: View {

    @ObservedObject var viewModel: RenameProgressViewModel
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Renaming Files...")
                .font(.headline)

            ProgressView(value: viewModel.progress, total: 1.0)
                .progressViewStyle(.linear)

            VStack(spacing: 4) {
                HStack {
                    Text("Renaming: \(viewModel.currentFile)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
                HStack {
                    Text("\(viewModel.renamedCount) of \(viewModel.photosToRename.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }

            if let error = viewModel.renameError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }

            HStack {
                Spacer()
                Button(viewModel.renameError != nil ? "Close" : "Cancel") {
                    viewModel.cancelRename()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .onAppear {
            viewModel.performRename()
        }
    }
}
