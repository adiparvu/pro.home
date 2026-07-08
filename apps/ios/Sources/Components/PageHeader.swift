import SwiftUI

struct PageHeader<Leading: View, Trailing: View>: View {
    private let title: String
    private var subtitle: String?
    private let leading: Leading
    private let trailing: Trailing
    private var _titleKey:    LocalizedStringKey?
    private var _subtitleKey: LocalizedStringKey?

    // Original call-site init — preserves all existing PageHeader(title:...) callers.
    init(title: String, subtitle: String? = nil,
         @ViewBuilder leading: () -> Leading = { EmptyView() },
         @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title    = title
        self.subtitle = subtitle
        self.leading  = leading()
        self.trailing = trailing()
        self._titleKey    = nil
        self._subtitleKey = nil
    }

    // LocalizedStringKey init — header updates reactively when env locale changes.
    init(titleKey: LocalizedStringKey, subtitleKey: LocalizedStringKey? = nil,
         @ViewBuilder leading: () -> Leading = { EmptyView() },
         @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title    = ""
        self.subtitle = nil
        self.leading  = leading()
        self.trailing = trailing()
        self._titleKey    = titleKey
        self._subtitleKey = subtitleKey
    }

    // Mixed init — dynamic title (user data) + localized subtitle key.
    init(title: String, subtitleKey: LocalizedStringKey,
         @ViewBuilder leading: () -> Leading = { EmptyView() },
         @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title    = title
        self.subtitle = nil
        self.leading  = leading()
        self.trailing = trailing()
        self._titleKey    = nil
        self._subtitleKey = subtitleKey
    }

    var body: some View {
        HStack(alignment: .bottom) {
            leading
            VStack(alignment: .leading, spacing: 3) {
                if let subtitleKey = _subtitleKey {
                    Text(subtitleKey)
                        .font(AppFont.label)
                        .foregroundStyle(.secondary)
                        .tracking(1.4)
                        .textCase(.uppercase)
                } else if let subtitle {
                    Text(LocalizedStringKey(subtitle))
                        .font(AppFont.label)
                        .foregroundStyle(.secondary)
                        .tracking(1.4)
                        .textCase(.uppercase)
                }
                if let titleKey = _titleKey {
                    Text(titleKey)
                        .font(AppFont.scaled(34, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                } else {
                    Text(title)
                        .font(AppFont.scaled(34, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.top, AppSpacing.sm)
    }
}
