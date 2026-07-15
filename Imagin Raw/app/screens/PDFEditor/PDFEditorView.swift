//
//  PDFEditorView.swift
//  Imagin Raw
//

import SwiftUI
import PDFKit

struct PDFEditorView: View {

    let photos: [PhotoItem]
    let albumName: String
    let cacheManager: PhotoCacheManager
    var onDismiss: (() -> Void)?

    @StateObject private var viewModel: PDFEditorViewModel

    init(photos: [PhotoItem], albumName: String, cacheManager: PhotoCacheManager, onDismiss: (() -> Void)? = nil) {
        self.photos = photos
        self.albumName = albumName
        self.cacheManager = cacheManager
        self.onDismiss = onDismiss
        _viewModel = StateObject(wrappedValue: PDFEditorViewModel(
            photos: photos,
            albumName: albumName,
            cacheManager: cacheManager
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            // PDF preview
            pdfPreview
            // Controls bar
            controlBar
        }
        .onAppear { viewModel.loadImages() }
        .onChange(of: viewModel.columns)      { _, _ in viewModel.rebuildPDF() }
        .onChange(of: viewModel.showFileName) { _, _ in viewModel.rebuildPDF() }
        .onChange(of: viewModel.showCheckbox) { _, _ in viewModel.rebuildPDF() }
        .fileExporter(
            isPresented: $viewModel.showExportPanel,
            document: viewModel.exportedFileDocument,
            contentType: .pdf,
            defaultFilename: "\(albumName).pdf"
        ) { result in
            if case .failure(let e) = result {
                viewModel.exportError = e.localizedDescription
            }
        }
        .alert("Export Error", isPresented: .constant(viewModel.exportError != nil)) {
            Button("OK") { viewModel.exportError = nil }
        } message: {
            Text(viewModel.exportError ?? "")
        }
    }

    // MARK: - PDF Preview

    @ViewBuilder
    private var pdfPreview: some View {
        if viewModel.isLoadingImages {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading images…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
        } else if let doc = viewModel.pdfDocument {
            PDFKitView(document: doc)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Color.black.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Control bar

    private var controlBar: some View {
        HStack(spacing: 16) {

            // Close
            Button {
                onDismiss?()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
            .help("Close PDF Editor")

            Divider().frame(height: 20)

            // Columns stepper
            HStack(spacing: 6) {
                Text("Columns")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Stepper(value: $viewModel.columns, in: 2...4) {
                    Text("\(viewModel.columns)")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 16)
                }
            }

            Divider().frame(height: 20)

            // Show file name
            Toggle(isOn: $viewModel.showFileName) {
                Text("Show name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .toggleStyle(.checkbox)

            Divider().frame(height: 20)

            // Show checkbox
            Toggle(isOn: $viewModel.showCheckbox) {
                Text("Show checkbox")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .toggleStyle(.checkbox)

            Spacer()

            // Photo count
            Text("\(photos.count) photo\(photos.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider().frame(height: 20)

            // Export button
            Button {
                viewModel.exportPDF()
            } label: {
                HStack(spacing: 6) {
                    if viewModel.isExporting {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                    Text("Export PDF")
                }
                .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isExporting || viewModel.pdfDocument == nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}

// MARK: - PDFKit bridge

private struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = NSColor(white: 0.15, alpha: 1)
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        if pdfView.document !== document {
            pdfView.document = document
        }
    }
}
