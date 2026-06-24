import SwiftUI

struct PageHeader: View {
    private let title: String
    private var subtitle: String?
    private var leading: AnyView?
    private var trailing: AnyView?
    private var _titleKey:    LocalizedStringKey?
    private var _subtitleKey: LocalizedStringKey?

    // Original call-site init — preserves all existing PageHeader(title:...) callers.
    init(title: String, subtitle: String? = nil,
         leading: AnyView? = nil, trailing: AnyView? = nil) {
        self.title    = title
        self.subtitle = subtitle
        self.leading  = leading
        self.trailing = trailing
        self._titleKey    = nil
        self._subtitleKey = nil
    }

    // LocalizedStringKey init — header updates reactively when env locale changes.
    init(titleKey: LocalizedStringKey, subtitleKey: LocalizedStringKey? = nil,
         leading: AnyView? = nil, trailing: AnyView? = nil) {
        self.title    = ""
        self.subtitle = nil
        self.leading  = leading
        self.trailing = trailing
        self._titleKey    = titleKey
        self._subtitleKey = subtitleKey
    }

    // Mixed init — dynamic title (user data) + localized subtitle key.
    init(title: String, subtitleKey: LocalizedStringKey,
         leading: AnyView? = nil, trailing: AnyView? = nil) {
        self.title    = title
        self.subtitle = nil
        self.leading  = leading
        self.trailing = trailing
        self._titleKey    = nil
        self._subtitleKey = subtitleKey
    }

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
