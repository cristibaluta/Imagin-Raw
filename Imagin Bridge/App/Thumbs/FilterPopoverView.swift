//
//  FilterPopoverView.swift
//  Imagin Bridge
//
//  Created by Cristian Baluta on 01.02.2026.
//

import SwiftUI

struct FilterPopoverView: View {
    @Binding var selectedLabels: Set<String>
    let photos: [PhotoItem]

    // All available labels in the requested order
    private let availableLabels = ["No Label", "Select", "Second", "Approved", "Review", "To Do", "To Delete"]

    // Calculate count for each label
    private func getCountForLabel(_ label: String) -> Int {
        if label == "No Label" {
            return photos.filter { photo in
                let photoLabel = photo.xmp?.label ?? ""
                return photoLabel.isEmpty && !photo.toDelete
            }.count
        } else if label == "To Delete" {
            return photos.filter { photo in
                return photo.toDelete
            }.count
        } else {
            return photos.filter { photo in
                let photoLabel = photo.xmp?.label ?? ""
                return photoLabel == label && !photo.toDelete
            }.count
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Filter by Labels")
                .font(.headline)
                .padding(.bottom, 4)

            ForEach(availableLabels, id: \.self) { label in
                let count = getCountForLabel(label)
                Toggle(isOn: Binding(
                    get: { selectedLabels.contains(label) },
                    set: { isSelected in
                        if isSelected {
                            selectedLabels.insert(label)
                        } else {
                            selectedLabels.remove(label)
                        }
                    }
                )) {
                    HStack {
                        Text(label)
                        if count > 0 {
                            Text("(\(count))")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .toggleStyle(CheckboxToggleStyle(label: label))
            }
        }
        .padding(16)
        .frame(minWidth: 100)
    }
}

struct CheckboxToggleStyle: ToggleStyle {
    let label: String

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            let labelColor = getColorForLabel(label)

            Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square.fill")
                .foregroundColor(labelColor)
                .font(.system(size: 16, weight: .medium))
                .onTapGesture {
                    configuration.isOn.toggle()
                }

            configuration.label
        }
    }

    private func getColorForLabel(_ label: String) -> Color {
        switch label {
        case "No Label":
            return .secondary
        case "Select":
            return .red
        case "Second":
            return .yellow
        case "Approved":
            return .green
        case "Review":
            return .blue
        case "To Do":
            return .purple
        case "To Delete":
            return .orange
        default:
            return .secondary
        }
    }
}
