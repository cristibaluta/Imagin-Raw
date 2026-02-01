//
//  NavigationDocumentModifier.swift
//  Bridge Replacement
//
//  Created by Cristian Baluta on 01.02.2026.
//

import SwiftUI

struct NavigationDocumentModifier: ViewModifier {
    let url: URL?
    
    func body(content: Content) -> some View {
        if let url = url {
            content.navigationDocument(url)
        } else {
            content
        }
    }
}