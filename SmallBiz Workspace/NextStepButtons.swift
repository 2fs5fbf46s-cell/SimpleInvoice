//
//  NextStepButtons.swift
//  SmallBiz Workspace
//

import SwiftUI

/// The buttons under a Next step: side by side when their labels fit on one
/// line, stacked when they don't. An HStack squeezed them instead, so labels
/// broke over two lines ("Record / Payment", "Esti-mate").
///
/// At accessibility text sizes they always stack: there the HStack was still
/// picked, and "Open Estimate" wrapped a syllable per line.
struct NextStepButtons<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) { content }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { content }
                VStack(alignment: .leading, spacing: 10) { content }
            }
        }
    }
}
