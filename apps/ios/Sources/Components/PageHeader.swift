import SwiftUI

struct PageHeader: View {
    let title: String
    var subtitle: String? = nil
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(1.2)
                }
                Text(title)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.primary)
            }
            Spacer()
            if let trailing {
                trailing
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}
