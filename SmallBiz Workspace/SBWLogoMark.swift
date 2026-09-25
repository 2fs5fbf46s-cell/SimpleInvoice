//
//  SBWLogoMark.swift
//  SmallBiz Workspace
//

import SwiftUI

/// The SmallBiz Workspace mark: two stacked cards (the work) with a check
/// (it's handled), on Evergreen. Drawn in code so the app icon, the launch
/// screen and every in-app logo come from one source.
///
/// `tile`: the rounded green square behind it. The app icon is rendered
/// full-bleed (iOS rounds the corners itself), so it passes `.square`.
struct SBWLogoMark: View {
    enum Tile { case rounded, square, none }
    var tile: Tile = .rounded

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height) / 64
            ZStack {
                switch tile {
                case .rounded:
                    RoundedRectangle(cornerRadius: 15 * s, style: .continuous).fill(SBWTheme.evergreen)
                case .square:
                    Rectangle().fill(SBWTheme.evergreen)
                case .none:
                    EmptyView()
                }
                // Back card.
                RoundedRectangle(cornerRadius: 5 * s, style: .continuous)
                    .fill(tile == .none ? SBWTheme.evergreen.opacity(0.35) : Color.white.opacity(0.35))
                    .frame(width: 30 * s, height: 22 * s)
                    .position(x: 30 * s, y: 27 * s)
                // Front card.
                RoundedRectangle(cornerRadius: 5 * s, style: .continuous)
                    .fill(tile == .none ? SBWTheme.evergreen : Color.white)
                    .frame(width: 30 * s, height: 26 * s)
                    .position(x: 34 * s, y: 35 * s)
                // Check.
                Path { p in
                    p.move(to: CGPoint(x: 26 * s, y: 35 * s))
                    p.addLine(to: CGPoint(x: 31 * s, y: 40 * s))
                    p.addLine(to: CGPoint(x: 41 * s, y: 29 * s))
                }
                .stroke(tile == .none ? Color.white : SBWTheme.evergreen,
                        style: StrokeStyle(lineWidth: 4 * s, lineCap: .round, lineJoin: .round))
            }
            .frame(width: 64 * s, height: 64 * s)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: 20) {
        SBWLogoMark().frame(width: 96)
        SBWLogoMark(tile: .none).frame(width: 96)
    }
    .padding()
}
