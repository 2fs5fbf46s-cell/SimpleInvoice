//
//  BrandingLoadView.swift
//  SmallBiz Workspace
//
//  Created by Javon Freeman on 1/23/26.
//

import SwiftUI

struct BrandingLoadView: View {
    let title: String
    let subtitle: String

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    Color(.secondarySystemBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 14) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)

                Text(title)
                    .font(.title3.weight(.semibold))

                HStack(spacing: 10) {
                    ProgressView()
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
            .padding(24)
        }
    }
}
