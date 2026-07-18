import SwiftUI

struct AuditLogView: View {
    @State private var events: [AuditLogService.AuditEvent] = []
    @State private var security = AccountSecurityService.shared
    @State private var showClearConfirm = false
    @State private var searchText = ""

    private var filteredEvents: [AuditLogService.AuditEvent] {
        guard !searchText.isEmpty else { return events }
        return events.filter {
            $0.description.matchesSearch(searchText)
                || $0.type.matchesSearch(searchText)
                || $0.deviceName.matchesSearch(searchText)
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            // The log is unbounded — a lazy stack keeps offscreen days
            // unmaterialized instead of building every row up front.
            // Headers are naked text (IMG_8559) — unpinned, so rows never
            // slide beneath bare glyphs.
            LazyVStack(alignment: .leading, spacing: 24) {
                // Account-level events come from the server journal
                // (`account_security_events`), so sign-ins and security
                // changes made on OTHER devices show up here too.
                if searchText.isEmpty, !security.recentEvents.isEmpty {
                    accountSection
                }
                if events.isEmpty {
                    emptyState
                } else {
                    ForEach(groupedByDay, id: \.0) { day, dayEvents in
                        daySection(day: day, events: dayEvents)
                    }
                }
                Spacer(minLength: 100)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Jurnal activitate")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: Text("Search…"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !events.isEmpty {
                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Text("Șterge tot")
                            .font(AppFont.scaled(14))
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .confirmationDialog("Șterge tot jurnalul?", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("Șterge tot", role: .destructive) {
                AuditLogService.shared.clear()
                events = []
            }
            Button("Anulează", role: .cancel) {}
        }
        .onAppear { events = AuditLogService.shared.events }
        .task { await security.loadRecentEvents() }
    }

    // MARK: - Account (server) events

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Account (all devices)")
                .font(AppFont.label)
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .padding(.leading, AppSpacing.sm)

            VStack(spacing: 0) {
                ForEach(Array(security.recentEvents.prefix(10).enumerated()), id: \.element.id) { idx, event in
                    if idx > 0 {
                        Rectangle()
                            .fill(Color.primary.opacity(AppOpacity.hairline))
                            .frame(height: 0.4)
                            .padding(.leading, 52)
                    }
                    accountEventRow(event)
                }
            }
            .liquidGlass(cornerRadius: AppRadius.xl)
        }
    }

    private func accountEventRow(_ event: AccountSecurityEvent) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accountEventColor(event.type).opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: accountEventIcon(event.type))
                    .font(AppFont.headline)
                    .foregroundStyle(accountEventColor(event.type))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(accountEventTitle(event.type))
                    .font(AppFont.footnote)
                    .foregroundStyle(.primary)
                HStack(spacing: 4) {
                    if let date = ISODate.date(from: event.createdAt) {
                        Text(date, format: .dateTime.day().month().hour().minute())
                            .font(AppFont.scaled(12))
                            .foregroundStyle(Color.primary.opacity(0.38))
                    }
                    if let device = event.payload?["device_name"], !device.isEmpty {
                        Text(verbatim: "· \(device)")
                            .font(AppFont.scaled(12))
                            .foregroundStyle(Color.primary.opacity(0.38))
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, AppSpacing.md)
    }

    private func accountEventTitle(_ type: String) -> LocalizedStringKey {
        switch type {
        case "new_device_login":          return "Sign-in on a new device"
        case "session_revoked":           return "Device removed from sessions"
        case "password_reset_requested":  return "Password reset requested"
        case "totp_enabled":              return "Authenticator app enabled"
        case "totp_disabled":             return "Authenticator app disabled"
        case "backup_codes_generated":    return "Backup codes generated"
        case "backup_code_used":          return "A backup code was used"
        default:                          return "Security event"
        }
    }

    private func accountEventIcon(_ type: String) -> String {
        switch type {
        case "new_device_login":         return "iphone.badge.exclamationmark"
        case "session_revoked":          return "iphone.slash"
        case "password_reset_requested": return "key.fill"
        case "totp_enabled":             return "lock.shield.fill"
        case "totp_disabled":            return "lock.open.fill"
        case "backup_codes_generated":   return "key.horizontal.fill"
        case "backup_code_used":         return "key.viewfinder"
        default:                         return "shield.fill"
        }
    }

    private func accountEventColor(_ type: String) -> Color {
        switch type {
        case "new_device_login":         return .orange
        case "session_revoked":          return .red
        case "password_reset_requested": return .orange
        case "totp_enabled":             return .indigo
        case "totp_disabled":            return .gray
        case "backup_codes_generated":   return .teal
        case "backup_code_used":         return .brandWarning
        default:                         return .purple
        }
    }

    // MARK: - Grouped data

    private var groupedByDay: [(String, [AuditLogService.AuditEvent])] {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        var dict: [(String, [AuditLogService.AuditEvent])] = []
        var seen: [String: Int] = [:]
        for event in filteredEvents {
            let key = formatter.string(from: event.timestamp)
            if let idx = seen[key] {
                dict[idx].1.append(event)
            } else {
                seen[key] = dict.count
                dict.append((key, [event]))
            }
        }
        return dict
    }

    // MARK: - Day section

    private func daySection(day: String, events: [AuditLogService.AuditEvent]) -> some View {
        Section {
            VStack(spacing: 0) {
                ForEach(Array(events.enumerated()), id: \.element.id) { idx, event in
                    if idx > 0 {
                        Rectangle()
                            .fill(Color.primary.opacity(AppOpacity.hairline))
                            .frame(height: 0.4)
                            .padding(.leading, 52)
                    }
                    eventRow(event)
                }
            }
            .liquidGlass(cornerRadius: AppRadius.xl)
        } header: {
            // Same treatment as the activity feed's day headers (IMG_8559):
            // naked text, no chip or band of any kind — the label sits
            // directly on the backdrop and scrolls with its rows.
            HStack {
                Text(day)
                    .font(AppFont.label)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, AppSpacing.xs)
        }
    }

    private func eventRow(_ event: AuditLogService.AuditEvent) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(iconColor(for: event.type).opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: iconName(for: event.type))
                    .font(AppFont.headline)
                    .foregroundStyle(iconColor(for: event.type))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(event.description)
                    .font(AppFont.footnote)
                    .foregroundStyle(.primary)
                HStack(spacing: 4) {
                    Text(timeString(from: event.timestamp))
                        .font(AppFont.scaled(12))
                        .foregroundStyle(Color.primary.opacity(0.38))
                    Text("·")
                        .font(AppFont.scaled(12))
                        .foregroundStyle(Color.primary.opacity(0.25))
                    Text(event.deviceName)
                        .font(AppFont.scaled(12))
                        .foregroundStyle(Color.primary.opacity(0.38))
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, AppSpacing.md)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        EmptyStateView(
            icon: "clock.badge.checkmark",
            title: "Nicio activitate înregistrată",
            message: "Activitățile de securitate vor apărea aici"
        )
    }

    // MARK: - Helpers

    private func iconName(for type: String) -> String {
        switch type {
        case "login":                    return "arrow.right.circle.fill"
        case "logout":                   return "arrow.left.circle.fill"
        case "export":                   return "square.and.arrow.up.fill"
        case "biometric_enabled":        return "faceid"
        case "biometric_disabled":       return "faceid"
        case "totp_enabled":             return "lock.shield.fill"
        case "totp_disabled":            return "lock.open.fill"
        case "password_reset_requested": return "key.fill"
        case "account_delete_attempted": return "trash.fill"
        case "autolock_changed":         return "timer"
        default:                         return "shield.fill"
        }
    }

    private func iconColor(for type: String) -> Color {
        switch type {
        case "login":                    return Color.brandSuccess
        case "logout":                   return .orange
        case "export":                   return .cyan
        case "biometric_enabled":        return .blue
        case "biometric_disabled":       return Color.primary.opacity(AppOpacity.mediumText)
        case "totp_enabled":             return .indigo
        case "totp_disabled":            return .gray
        case "password_reset_requested": return .orange
        case "account_delete_attempted": return .red
        case "autolock_changed":         return .cyan
        default:                         return .purple
        }
    }

    private func timeString(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
