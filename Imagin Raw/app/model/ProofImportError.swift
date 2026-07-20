//
//  ProofImportError.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 20.07.2026.
//

import PDFKit

enum ProofImportError: Error {
    case couldNotOpenPDF
}

struct ProofPDFImporter {

    static func selectedIDs(from url: URL) throws -> [String] {

        guard let document = PDFDocument(url: url) else {
            throw ProofImportError.couldNotOpenPDF
        }

        var selected: [String] = []

        for pageIndex in 0..<document.pageCount {

            guard let page = document.page(at: pageIndex) else {
                continue
            }

            for annotation in page.annotations {

                guard annotation.widgetFieldType == .button else {
                    continue
                }

                if annotation.buttonWidgetState == .onState {
                    if let id = annotation.fieldName {
                        selected.append(id)
                    }
                }
            }
        }

        return selected
    }
}
