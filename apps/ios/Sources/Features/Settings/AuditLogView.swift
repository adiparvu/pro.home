import SwiftUI

struct AuditLogView: View {
    @State private var events: [AuditLogService.AuditEvent] = []
    @State private var showClearConfirm = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !events.isEmpty {
                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Text("Șterge tot")
                            .font(.system(size: 14))
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
    }

    // MARK: - Grouped data

    private var groupedByDay: [(String, [AuditLogService.AuditEvent])] {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        var dict: [(String, [AuditLogService.AuditEvent])] = []
        var seen: [String: Int] = [:]
        for event in events {
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
        VStack(alignment: .leading, spacing: 8) {
            Text(day)
                .textCase(.uppercase)
                .font(AppFont.label)
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .padding(.leading, AppSpacing.sm)

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
            .liquidGlass(cornerRadius: 20)
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
                        .font(.system(size: 12))
                        .foregroundStyle(Color.primary.opacity(0.38))
                    Text("·")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.primary.opacity(0.25))
                    Text(event.deviceName)
                        .font(.system(size: 12))
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
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(AppOpacity.hairline))
                    .frame(width: 64, height: 64)
                Image(systemName: "clock.badge.checkmark")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.primary.opacity(0.3))
            }
            Text("Nicio activitate înregistrată")
                .font(AppFont.body)
                .foregroundStyle(.primary)
            Text("Activitățile de securitate vor apărea aici")
                .font(.system(size: 13))
                .foregroundStyle(Color.primary.opacity(0.4))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
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
        case "login":                    return Color(red: 0.3, green: 0.82, blue: 0.45)
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
