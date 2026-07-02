//
//  VideoEditorView.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 02.07.2026.
//

import SwiftUI
import UniformTypeIdentifiers

struct VideoEditorView: View {

    @StateObject private var viewModel: VideoEditorViewModel
    @State private var exportSavePanel = false
    var onDismiss: (() -> Void)?

    init(photos: [PhotoItem], cacheManager: PhotoCacheManager, onDismiss: (() -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: VideoEditorViewModel(photos: photos, cacheManager: cacheManager))
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top separator
            Rectangle()
                .fill(Color.secondary.opacity(0.25))
                .frame(height: 1)

            // Main preview area
            ZStack {
                Color.black
                if viewModel.isLoadingImages {
                    ProgressView("Loading frames…")
                        .foregroundStyle(.white)
                } else if viewModel.images.isEmpty {
                    Text("No images available")
                        .foregroundStyle(.secondary)
                } else {
                    currentFrameView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Bottom control bar
            controlBar
        }
        .onAppear {
            viewModel.loadImages()
        }
        .onDisappear {
            viewModel.stopPlayback()
        }
        #if os(macOS)
        .fileExporter(
            isPresented: $exportSavePanel,
            document: VideoExportDocument(),
            contentType: .mpeg4Movie,
            defaultFilename: "Timelapse.mp4"
        ) { result in
            switch result {
            case .success(let url):
                viewModel.exportVideo(to: url)
            case .failure(let error):
                viewModel.exportError = error.localizedDescription
            }
        }
        #endif
        .alert("Export Error", isPresented: Binding<Bool>(
            get: { viewModel.exportError != nil },
            set: { if !$0 { viewModel.exportError = nil } }
        )) {
            Button("OK") { viewModel.exportError = nil }
        } message: {
            Text(viewModel.exportError ?? "")
        }
    }

    private var qualityLabel: String {
        switch viewModel.quality {
        case 0..<0.35: return "Low"
        case 0.35..<0.65: return "Medium"
        case 0.65..<0.85: return "High"
        default: return "Max"
        }
    }

    // MARK: - Current frame

    @ViewBuilder
    private var currentFrameView: some View {
        let images = viewModel.images
        let idx = min(viewModel.currentFrameIndex, images.count - 1)
        let img = images[idx]
        #if os(macOS)
        Image(nsImage: img)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .id(idx)
        #else
        Image(uiImage: img)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .id(idx)
        #endif
    }

    // MARK: - Control bar

    private var controlBar: some View {
        VStack(spacing: 0) {
            // Thin separator
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 1)

            HStack(spacing: 20) {
                // Close button
                if let onDismiss {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Close Video Editor")
                }

                // FPS control
                HStack(spacing: 6) {
                    Slider(
                        value: $viewModel.fps,
                        in: viewModel.minFPS...viewModel.maxFPS
                    )
                    .frame(width: 100)
                    .onChange(of: viewModel.fps) { _, _ in
                        // Restart playback with new rate if currently playing
                        if viewModel.isPlaying {
                            viewModel.stopPlayback()
                            viewModel.togglePlayback()
                        }
                    }
                    Text("\(Int(viewModel.fps))fps")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.primary)
                }

                Divider()
                    .frame(height: 20)

                // Quality control
                HStack(spacing: 6) {
                    Text("Quality")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $viewModel.quality, in: 0.0...1.0)
                        .frame(width: 100)
                    Text(qualityLabel)
                        .font(.caption)
                        .foregroundStyle(.primary)
                }

                Divider()
                    .frame(height: 20)

                // Frame counter
                if !viewModel.images.isEmpty {
                    Text("\(viewModel.currentFrameIndex + 1) / \(viewModel.images.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Play / Stop
                Button {
                    viewModel.togglePlayback()
                } label: {
                    Image(systemName: viewModel.isPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 14))
                }
                .disabled(viewModel.images.count < 2)
                .buttonStyle(.plain)
                .keyboardShortcut(.space, modifiers: [])
                .help(viewModel.isPlaying ? "Stop Preview" : "Play Preview")

                Divider()
                    .frame(height: 20)

                // Export
                if viewModel.isExporting {
                    HStack(spacing: 6) {
                        ProgressView(value: viewModel.exportProgress)
                            .frame(width: 80)
                        Text("Exporting…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button {
                        exportSavePanel = true
                    } label: {
                        Label("Export Video", systemImage: "square.and.arrow.up")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.images.isEmpty)
                    .help("Export as MP4")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial)
        }
        .frame(height: 40)
    }
}

// MARK: - Dummy FileDocument for the save panel

#if os(macOS)
import UniformTypeIdentifiers

struct VideoExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.mpeg4Movie] }
    init() {}
    init(configuration: ReadConfiguration) throws {}
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data())
    }
}
#endif
