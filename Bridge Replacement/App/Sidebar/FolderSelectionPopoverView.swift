//
//  FolderSelectionPopoverView.swift
//  Imagin Bridge
//
//  Created by Cristian Baluta on 31.01.2026.
//

import SwiftUI

struct FolderSelectionPopoverView: View {
    @ObservedObject var model: BrowserModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Select Folder")
                    .font(.headline)
                    .padding(.leading, 16)
                    .padding(.top, 12)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .padding(.trailing, 16)
                .padding(.top, 12)
            }

            Divider()
                .padding(.top, 8)

            // Reuse the existing SidebarView
            SidebarView(model: model)
                .padding(.top, 8)
        }
        .frame(width: 300, height: 400)
        .background(Color(NSColor.controlBackgroundColor))
    }
}
