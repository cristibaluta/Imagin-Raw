//
//  FilterPopoverView.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 01.02.2026.
//

import SwiftUI

struct FilterPopoverView: View {
    @Binding var selectedLabels: Set<PhotoLabel>
    @Binding var selectedRatings: Set<Int>
    @Binding var selectedNames: Set<String>
    @State private var importingPdf = false
    let photos: [PhotoItem]

    private let availableLabels = PhotoLabel.allCases
    private let availableRatings = 1...5

    /// Calculate count for each label
    private func numberOfPhotos(with label: PhotoLabel) -> Int {
        if label == .noLabel {
            return photos.count(where: { photo in
                let photoLabel = photo.xmp?.label ?? ""
                return photoLabel.isEmpty && photo.state != .rejected
            })
        }
        else if label == .rejected {
            return photos.count(where: { $0.state == .rejected })
        }
        else {
            return photos.count(where: { photo in
                let photoLabel = photo.xmp?.label ?? ""
                return photoLabel == label.rawValue && photo.state != .rejected
            })
        }
    }

    /// Calculate count for each rating
    private func numberOfPhotos(with rating: Int) -> Int {
        photos.count(where: { $0.effectiveRating == rating })
    }

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            // Labels column
            VStack(alignment: .leading, spacing: 12) {
                Text("Filter by Labels")
                    .font(.headline)
                    .padding(.bottom, 4)

                ForEach(availableLabels, id: \.self) { label in
                    let count = numberOfPhotos(with: label)
                    Toggle(isOn: Binding(
                        get: {
                            selectedLabels.contains(label)
                        },
                        set: { isSelected in
                            if isSelected {
                                selectedLabels.insert(label)
                            } else {
                                selectedLabels.remove(label)
                            }
                        }
                    )) {
                        HStack {
                            Text(label.rawValue)
                            if count > 0 {
                                Text("(\(count))")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .toggleStyle(CheckboxToggleStyle(label: label.rawValue))
                }
            }

            Divider()

            // Ratings column
            VStack(alignment: .leading, spacing: 12) {
                Text("Filter by Rating")
                    .font(.headline)
                    .padding(.bottom, 4)

                ForEach(availableRatings, id: \.self) { rating in
                    let count = numberOfPhotos(with: rating)
                    Toggle(isOn: Binding(
                        get: {
                            selectedRatings.contains(rating)
                        },
                        set: { isSelected in
                            if isSelected {
                                selectedRatings.insert(rating)
                            } else {
                                selectedRatings.remove(rating)
                            }
                        }
                    )) {
                        HStack(spacing: 4) {
                            // Show stars
                            ForEach(availableRatings, id: \.self) { star in
                                Image(systemName: star <= rating ? "star.fill" : "star")
                                    .foregroundColor(star <= rating ? .primary : .gray)
                                    .font(.system(size: 10))
                            }
                            if count > 0 {
                                Text("(\(count))")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .toggleStyle(RatingCheckboxToggleStyle())
                }

                Spacer()

                if selectedNames.count > 0 {
                    Button("Clear Proof PDF") {
                        selectedNames.removeAll()
                    }
                } else {
                    Button("Import Proof PDF") {
                        importingPdf = true
                    }
                    .fileImporter(
                        isPresented: $importingPdf,
                        allowedContentTypes: [.pdf],
                        allowsMultipleSelection: false
                    ) { result in
                        switch result {
                            case .success(let urls):

                                guard let url = urls.first else {
                                    return
                                }
                                guard url.startAccessingSecurityScopedResource() else {
                                    return
                                }
                                defer {
                                    url.stopAccessingSecurityScopedResource()
                                }

                                do {
                                    let ids = try ProofPDFImporter.selectedIDs(from: url)
                                    selectedNames = Set(ids)
                                } catch {
                                }
                            case .failure(_):
                                break
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(minWidth: 350)
    }
}

struct CheckboxToggleStyle: ToggleStyle {
    let label: String

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            let labelColor = PhotoLabel(rawValue: label)?.color

            Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square.fill")
                .foregroundColor(labelColor)
                .font(.system(size: 16, weight: .medium))
                .onTapGesture {
                    configuration.isOn.toggle()
                }

            configuration.label
        }
    }
}

struct RatingCheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                .foregroundColor(configuration.isOn ? .primary : .secondary)
                .font(.system(size: 16, weight: .medium))
                .onTapGesture {
                    configuration.isOn.toggle()
                }

            configuration.label
        }
    }
}
