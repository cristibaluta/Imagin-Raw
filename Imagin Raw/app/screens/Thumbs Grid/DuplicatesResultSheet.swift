//
//  DuplicatesResultSheet.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 09.03.2026.
//

import SwiftUI

struct DuplicatesResultSheet: View {
    @ObservedObject var viewModel: ThumbGridViewModel
    @Environment(\.dismiss) private var dismiss

    private var isWaitingForThumbs: Bool {
        viewModel.cachingQueueCount > 0 && viewModel.duplicateScanProgress.done == 0
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "rectangle.on.rectangle.angled")
                .font(.system(size: 36))
                .foregroundColor(.secondary)

            if isWaitingForThumbs {
                Text("Preparing Thumbnails")
                    .font(.headline)

                ProgressView()
                    .progressViewStyle(.linear)
                    .frame(width: 300)

                Text("Generating thumbnails… \(viewModel.cachingQueueCount) remaining")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Finding Duplicates")
                    .font(.headline)

                ProgressView(value: Double(viewModel.duplicateScanProgress.done),
                             total: Double(max(1, viewModel.duplicateScanProgress.total)))
                    .progressViewStyle(.linear)
                    .frame(width: 300)

                Text("Analysing \(viewModel.duplicateScanProgress.done) / \(viewModel.duplicateScanProgress.total) photos...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .padding(.bottom)
        }
        .frame(width: 400, height: 300)
        .onChange(of: viewModel.isFindingDuplicates) { _, isRunning in
            // Auto-dismiss when the scan finishes
            if !isRunning {
                dismiss()
            }
        }
    }
}
