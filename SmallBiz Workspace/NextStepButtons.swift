//
//  NextStepButtons.swift
//  SmallBiz Workspace
//

import SwiftUI

/// The buttons under a Next step: side by side when their labels fit on one
/// line, stacked when they don't. An HStack squeezed them instead, so labels
/// broke over two lines ("Record / Payment", "Esti-mate").
struct NextStepButtons<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { content }
            VStack(alignment: .leading, spacing: 10) { content }
        }
    }
}
