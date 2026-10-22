import SwiftUI

struct TokenDetailRow: View {
    let title: String
    let value: String
    var secondary = false
    var body: some View {
        HStack {
            Text(title).foregroundStyle(secondary ? Color.secondary : .primary)
            Spacer()
            Text(value).font(secondary ? EnergyTypography.Detail.caption : EnergyTypography.Detail.rowValue).monospacedDigit().foregroundStyle(secondary ? Color.secondary : .primary).textSelection(.enabled)
        }.font(secondary ? EnergyTypography.Detail.caption : EnergyTypography.Detail.body)
            .padding(.vertical, secondary ? 7 : 11).padding(.horizontal, 2)
    }
}
