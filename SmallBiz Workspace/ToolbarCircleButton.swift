import SwiftUI

struct ToolbarCircleButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(Color.white)
                .clipShape(Circle())
                .shadow(
                    color: Color.black.opacity(0.08),
                    radius: 6,
                    x: 0,
                    y: 3
                )
        }
        .buttonStyle(.plain)          // ✅ removes the system “pill” background
        .contentShape(Circle())       // ✅ keeps tap target circular
    }
}
