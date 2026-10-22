import SwiftUI

struct PanelEmptyState: View {
    let title: String
    let systemImage: String
    let description: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage).font(EnergyTypography.Icon.empty).foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(title).font(EnergyTypography.Detail.title)
            Text(description).font(EnergyTypography.Detail.body).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).lineSpacing(3)
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
    }
}
