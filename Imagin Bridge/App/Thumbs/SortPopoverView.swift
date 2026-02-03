//
//  SortPopoverView.swift
//  Imagin Bridge
//
//  Created by Cristian Baluta on 01.02.2026.
//

import SwiftUI

struct SortPopoverView: View {
    @Binding var sortOption: ThumbGridView.SortOption

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sort Photos")
                .font(.headline)
                .padding(.bottom, 4)

            // Sort by options
            VStack(alignment: .leading, spacing: 8) {
                ForEach(ThumbGridView.SortOption.allCases, id: \.self) { option in
                    Button(action: {
                        sortOption = option
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
        .padding(16)
        .frame(minWidth: 200)
    }
}

#Preview {
    SortPopoverView(sortOption: .constant(.name))
}
