//
//  GridTypePopoverView.swift
//  Imagin Bridge
//
//  Created by Cristian Baluta on 03.02.2026.
//

import SwiftUI

struct GridTypePopoverView: View {
    @Binding var gridType: ThumbGridViewModel.GridType
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Grid Layout")
                .font(.headline)
                .padding(.bottom, 4)
            
            ForEach(ThumbGridViewModel.GridType.allCases) { type in
                Button(action: {
                    gridType = type
                    dismiss()
                }) {
                    HStack {
                        Image(systemName: gridType == type ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(gridType == type ? .accentColor : .secondary)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(type.displayName)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.primary)
                            
                            Text("\(type.thumbSize, specifier: "%.0f")px thumbnails")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.vertical, 4)
            }
        }
        .padding(16)
        .frame(width: 200)
    }
}
