//
//  StarRatingView.swift
//  Imagin Bridge
//
//  Created by Cristian Baluta on 03.02.2026.
//

import SwiftUI

struct StarRatingView: View {
    let rating: Int
    let maxRating: Int
    let starSize: CGFloat
    let onRatingChanged: (Int) -> Void
    
    @State private var hoverRating: Int = 0
    
    var body: some View {
        HStack(spacing: 2) {
            // Stars 1-5
            ForEach(1...maxRating, id: \.self) { index in
                Button(action: {
                    onRatingChanged(index)
                }) {
                    Image(systemName: "star.fill")
                        .font(.system(size: starSize))
                        .foregroundColor(starColor(for: index))
                }
                .buttonStyle(PlainButtonStyle())
                .onHover { hovering in
                    if hovering {
                        hoverRating = index
                    } else {
                        hoverRating = 0
                    }
                }
            }
            
            // X button to clear rating
            if rating > 0 {
                Button(action: {
                    onRatingChanged(0)
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: starSize - 2, weight: .bold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
    
    private func starColor(for index: Int) -> Color {
        if hoverRating > 0 {
            return index <= hoverRating ? .yellow : .gray.opacity(0.3)
        } else {
            return index <= rating ? .yellow : .gray.opacity(0.3)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        StarRatingView(rating: 0, maxRating: 5, starSize: 16) { _ in }
        StarRatingView(rating: 3, maxRating: 5, starSize: 16) { _ in }
        StarRatingView(rating: 5, maxRating: 5, starSize: 16) { _ in }
    }
    .padding()
}