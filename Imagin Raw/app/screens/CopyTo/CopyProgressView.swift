//
//  CopyProgressView.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 06.08.2026.
//

import SwiftUI

struct CopyProgressView: View {
    @ObservedObject var viewModel: PhotoCopySheetModel
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Copying Files...").font(.headline)

            if viewModel.backupDestinationURL != nil {
                Text("Copying to primary and backup destinations")
                    .font(.caption).foregroundColor(.secondary)
            }

            ProgressView(value: viewModel.copyProgress, total: 1.0)
                .progressViewStyle(.linear)
                .frame(height: 8)

            VStack(spacing: 4) {
                HStack {
                    Text("Copying: \(viewModel.currentFile)")
                        .font(.caption).foregroundColor(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                }
                HStack {
                    Text("\(viewModel.copiedCount) of \(viewModel.totalCount)")
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                }
            }

            if let error = viewModel.copyError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                    Text(error).font(.caption).foregroundColor(.secondary).lineLimit(2)
                    Spacer()
                }
            }

            HStack {
                Spacer()
                Button(viewModel.copyError != nil ? "Close" : "Cancel") {
                    if viewModel.copyError == nil {
                        viewModel.cancel()
                    }
                    onDone()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
    }
}
