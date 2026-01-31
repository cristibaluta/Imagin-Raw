//
//  LargePreviewView.swift
//  Imagin Bridge
//
//  Created by Cristian Baluta on 30.01.2026.
//

import SwiftUI

struct LargePreviewView: View {
    let photo: PhotoItem
    @State private var preview: NSImage?

    var body: some View {
        VStack {
//            Text(photo.path)
            if let nsImage = preview {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .padding()
            } else {
                ProgressView()
                    .onAppear() {
                        DispatchQueue.main.async {
                            if let data = RawWrapper().extractEmbeddedJPEG(self.photo.path) {
                                let img = NSImage(data: data)
                                DispatchQueue.main.async {
                                    self.preview = img
                                }
                            }
                        }
                    }
            }
        }
//        .background(Rectangle().fill(Color.black).opacity(0.8))
    }
}
