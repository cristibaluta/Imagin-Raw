//
//  EmptyStateView.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 17.03.2026.
//

import SwiftUI

struct EmptyStateView: View {
    @StateObject var viewModel: ThumbGridViewModel

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text(viewModel.photos.isEmpty ? "No Supported Photos Found" : "No Photos Match Current Filter")
                    .font(.headline)
                    .foregroundColor(.primary)

                if viewModel.photos.isEmpty {
                    Text("Supported formats: RAW files, JPEG, PNG, TIFF, HEIC, MOV, and more.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Try adjusting your filter settings to see more photos.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            Spacer()
        }
    }
}
