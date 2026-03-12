//
//  ExportPanelView.swift
//  Imagin Raw
//

import SwiftUI

struct ExportPanelView: View {
    let photo: PhotoItem
    let pixelSize: CGSize
    @Binding var isPresented: Bool
    @Binding var selectedRatio: ExportAspectRatio
    @Binding var padding: Double
    @Binding var alignment: ExportAlignment

    @State private var isExporting = false
    @State private var exportResult: ExportResult? = nil

    private enum ExportResult {
        case success(URL)
        case failure(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // Header
            HStack {
                Text("Export for Instagram")
                    .font(.headline)
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
                .buttonStyle(PlainButtonStyle())
            }

            Divider()

            // Aspect ratio picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Aspect Ratio")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(spacing: 6) {
                    ForEach(ExportAspectRatio.allCases) { ratio in
                        Button(action: { selectedRatio = ratio }) {
                            Text(ratio.rawValue)
                                .font(.system(size: 12, weight: selectedRatio == ratio ? .semibold : .regular))
                                .foregroundColor(selectedRatio == ratio ? .primary : .secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(selectedRatio == ratio ? Color.accentColor.opacity(0.15) : Color.clear)
                        }
                        .buttonStyle(PlainButtonStyle())
                        if ratio != ExportAspectRatio.allCases.last {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.3))
                                .frame(width: 1, height: 14)
                        }
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                )
            }

            // Padding slider
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Padding")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(padding)) px")
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundColor(.primary)
                }
                Slider(value: $padding, in: 0...100, step: 5)
                    .controlSize(.small)
            }

            // Alignment picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Alignment")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                HStack(spacing: 6) {
                    ForEach(ExportAlignment.allCases) { option in
                        Button(action: { alignment = option }) {
                            Image(systemName: option.systemImage)
                                .font(.system(size: 13, weight: alignment == option ? .semibold : .regular))
                                .foregroundColor(alignment == option ? .primary : .secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(alignment == option ? Color.accentColor.opacity(0.15) : Color.clear)
                        }
                        .buttonStyle(PlainButtonStyle())
                        if option != ExportAlignment.allCases.last {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.3))
                                .frame(width: 1, height: 14)
                        }
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                )
            }

            // Canvas preview label
            if let info = canvasInfo {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("Canvas: \(info)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Result feedback
            if let result = exportResult {
                HStack(spacing: 6) {
                    switch result {
                    case .success(let url):
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Saved: \(url.lastPathComponent)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    case .failure(let msg):
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Text(msg)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }

            // Save button
            HStack {
                Spacer()
                Button(action: export) {
                    HStack(spacing: 6) {
                        if isExporting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "square.and.arrow.down")
                        }
                        Text(isExporting ? "Exporting…" : "Save as PNG")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isExporting)
            }
        }
        .padding(16)
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)
        )
    }

    // MARK: - Canvas preview

    private var canvasInfo: String? {
        let srcW = pixelSize.width
        let srcH = pixelSize.height
        let pad = CGFloat(Int(padding))
        let paddedW = srcW + pad * 2
        let paddedH = srcH + pad * 2
        var canvasW = paddedW
        var canvasH = paddedH
        if let ratio = selectedRatio.ratio {
            let r = paddedW / paddedH
            if r > ratio {
                canvasH = paddedW / ratio
            } else if r < ratio {
                canvasW = paddedH * ratio
            }
        }
        return "\(Int(canvasW)) × \(Int(canvasH))"
    }

    // MARK: - Export

    private func export() {
        isExporting = true
        exportResult = nil
        let path = photo.path
        let ratio = selectedRatio
        let pad = Int(padding)
        let align = alignment
        let outputURL = ExportService.outputURL(for: path)

        Task.detached(priority: .userInitiated) {
            do {
                try ExportService.export(
                    sourcePath: path,
                    targetRatio: ratio,
                    padding: pad,
                    alignment: align,
                    outputURL: outputURL
                )
                await MainActor.run {
                    isExporting = false
                    exportResult = .success(outputURL)
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    exportResult = .failure(error.localizedDescription)
                }
            }
        }
    }
}
