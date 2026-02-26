import SwiftUI

extension SummaryKit {
struct SummaryHeader: View {
    let title: String
    let subtitle: String?
    let status: String?

    init(title: String, subtitle: String? = nil, status: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.status = status
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let status, !status.isEmpty {
                SummaryKit.StatusChip(text: status)
            }
        }
    }
}
}
