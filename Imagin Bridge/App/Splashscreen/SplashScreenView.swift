//
//  SplashScreenView.swift
//  Imagin Bridge
//
//  Created by Cristian Baluta on 02.02.2026.
//

import SwiftUI

struct SplashScreenView: View {
    @ObservedObject var model: BrowserModel
    @State private var showingFolderPicker = false
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            // App icon/logo area
            VStack(spacing: 20) {
                Image("Logo")
                    .font(.system(size: 80, weight: .light))
                    .foregroundColor(.accentColor)
                
                VStack(spacing: 8) {
                    Text("Bridge")
                        .font(.largeTitle)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text("Photo Browser & Organizer")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }
            
            // Welcome content
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("To get started, add folders containing your photos. RAW files, JPEG, and other formats are supported")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .multilineTextAlignment(.center)
                
                // Call to action button
                Button(action: {
                    showingFolderPicker = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 16, weight: .medium))
                        Text("Add Your First Folder")
                            .font(.system(size: 16, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .cornerRadius(8)
                    .shadow(color: .accentColor.opacity(0.3), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(PlainButtonStyle())
                .scaleEffect(1.0)
                .onHover { isHovered in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        // Could add hover effects here if needed
                    }
                }
            }
            
            Spacer()
            
            // Footer
            Text("Tip: You can add multiple photo folders or directly your Photos root folder")
                .font(.caption)
                .foregroundColor(.primary)
            .multilineTextAlignment(.center)
            
            Spacer().frame(height: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .fileImporter(
            isPresented: $showingFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    model.addFolder(at: url)
                }
            case .failure(let error):
                print("Failed to select folder: \(error)")
            }
        }
    }
}
