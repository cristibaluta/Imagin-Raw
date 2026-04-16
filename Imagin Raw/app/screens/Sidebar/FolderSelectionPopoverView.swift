//
//  FolderSelectionPopoverView.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 31.01.2026.
//

import SwiftUI

struct FolderSelectionPopoverView: View {
    @EnvironmentObject var filesModel: FilesModel
    @Environment(\.dismiss) private var dismiss
    @State private var initialSelectedFolder: FolderItem?

    var body: some View {
        FoldersListView(onDoubleClick: nil)
            .onAppear {
                // Store the initial selected folder when popover opens
                initialSelectedFolder = filesModel.selectedFolder
            }
            .onChange(of: filesModel.selectedFolder) { oldValue, newValue in
                // Only close if the selection actually changed from the initial value
                if let newValue = newValue, newValue.id != initialSelectedFolder?.id {
                    dismiss()
                }
            }
    }
}
