//
//  SortPopoverView.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 01.02.2026.
//

import SwiftUI

struct SortPopoverView: View {
    @Binding var sortOption: ThumbGridViewModel.SortOption
    @EnvironmentObject var filesModel: FilesModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(alignment: .top, spacing: 24) {

            // Sidebar folders sort column
            VStack(alignment: .leading, spacing: 12) {
                Text("Sort Folders")
                    .font(.headline)
                    .padding(.bottom, 4)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(FilesModel.SidebarSortOption.allCases, id: \.self) { option in
                        Button(action: {
                            filesModel.sidebarSortOption = option
                            appPrefs.set(option.rawValue, forKey: .sidebarSortOption)
                            dismiss()
                        }) {
                            HStack {
                                Image(systemName: filesModel.sidebarSortOption == option ? "circle.fill" : "circle")
                                    .foregroundColor(filesModel.sidebarSortOption == option ? .blue : .gray)
                                Text(option.displayName)
                                Spacer()
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }

            Divider()

            // Photos sort column
            VStack(alignment: .leading, spacing: 12) {
                Text("Sort Photos")
                    .font(.headline)
                    .padding(.bottom, 4)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(ThumbGridViewModel.SortOption.allCases, id: \.self) { option in
                        Button(action: {
                            sortOption = option
                            dismiss()
                        }) {
                            HStack {
                                Image(systemName: sortOption == option ? "circle.fill" : "circle")
                                    .foregroundColor(sortOption == option ? .blue : .gray)
                                Text(option.rawValue)
                                Spacer()
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
        .padding(16)
        .frame(minWidth: 380)
    }
}
