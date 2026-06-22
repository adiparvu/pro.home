import SwiftUI

struct PageHeader: View {
    let title: String
    var subtitle: String? = nil
    var leading: AnyView? = nil
    var trailing: AnyView? = nil

    // Backing storage for the LocalizedStringKey variant — nil when using plain String init.
    fileprivate var _titleKey:    LocalizedStringKey? = nil
    fileprivate var _subtitleKey: LocalizedStringKey? = nil

    var body: some View {
        HStack(alignment: .bottom) {
            if let leading { leading }
            VStack(alignment: .leading, spacing: 3) {
                if let subtitleKey = _subtitleKey {
                    Text(subtitleKey)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(1.4)
                        .textCase(.uppercase)
                } else if let subtitle {
                    Text(subtitle.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(1.4)
                }
                if let titleKey = _titleKey {
                    Text(titleKey)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                } else {
                    Text(title)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }
            }
            Spacer()
            if let trailing { trailing }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}

// Extension preserves the synthesized memberwise init(title:subtitle:leading:trailing:)
// for all existing call sites while adding the LocalizedStringKey convenience.
extension PageHeader {
    init(titleKey: LocalizedStringKey, subtitleKey: LocalizedStringKey? = nil,
         leading: AnyView? = nil, trailing: AnyView? = nil) {
        self.title    = ""
        self.subtitle = nil
        self.leading  = leading
        self.trailing = trailing
        self._titleKey    = titleKey
        self._subtitleKey = subtitleKey
    }
}
