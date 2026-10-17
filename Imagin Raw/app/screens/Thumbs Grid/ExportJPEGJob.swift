//
//  ExportJPEGJob.swift
//  Imagin Raw
//

import SwiftUI

/// Exports the largest embedded JPEG of raw files into a folder, reporting progress and supporting cancellation.
@MainActor
final class ExportJPEGJob: ObservableObject, Identifiable {

    let id = UUID()
    let paths: [String]
    let destination: URL

    @Published private(set) var completed = 0
    @Published private(set) var failed = 0
    @Published private(set) var isFinished = false
    @Published private(set) var isCancelled = false

    private var task: Task<Void, Never>?
    var onFinished: ((ExportJPEGJob) -> Void)?

    init(paths: [String], destination: URL) {
        self.paths = paths
        self.destination = destination
    }

    var total: Int { paths.count }

    func start() {
        let paths = self.paths
        let destination = self.destination
        task = Task.detached(priority: .userInitiated) { [weak self] in
            let fm = FileManager.default
            for path in paths {
                if Task.isCancelled {
                    break
                }
                var ok = false
                if let data = RawWrapper.shared().extractLargestEmbeddedJPEG(atPath: path) {
                    let base = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                    var dest = destination.appendingPathComponent(base + ".jpg")
                    var n = 1
                    while fm.fileExists(atPath: dest.path) {
                        dest = destination.appendingPathComponent("\(base)_\(n).jpg")
                        n += 1
                    }
                    ok = (try? data.write(to: dest)) != nil
                }
                let success = ok
                await MainActor.run { [weak self] in
                    self?.completed += 1
                    if !success {
                        self?.failed += 1
                    }
                }
            }
            await MainActor.run { [weak self] in
                guard let self else {
                    return
                }
                self.isCancelled = Task.isCancelled
                self.isFinished = true
                self.onFinished?(self)
            }
        }
    }

    func cancel() {
        isCancelled = true
        task?.cancel()
    }
}

struct ExportJPEGProgressView: View {
    @ObservedObject var job: ExportJPEGJob

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Exporting embedded JPEGs")
                .font(.headline)
            ProgressView(value: Double(job.completed), total: Double(max(job.total, 1)))
            HStack {
                Text("\(job.completed) of \(job.total)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Cancel") {
                    job.cancel()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(job.isCancelled)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}
