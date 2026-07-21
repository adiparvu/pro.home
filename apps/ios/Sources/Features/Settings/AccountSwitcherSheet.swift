import SwiftUI
import Supabase

struct AccountSwitcherSheet: View {
    @Environment(AuthService.self) private var auth
    private let store = AccountsStore.shared
    @Binding var showAddAccount: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var switchError: String?
    @State private var isSwitching = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.accounts) { account in
                        let isCurrent = account.userId == auth.session?.user.id.uuidString
                        AccountRow(
                            account: account,
                            isCurrent: isCurrent,
                            isSwitching: isSwitching
                        ) {
                            guard !isCurrent else { return }
                            Task { await switchTo(account) }
                        }
                        // Any saved account except the one you're signed into can
                        // be removed from the device here — a stale account (e.g.
                        // one you logged out of on another build) shouldn't linger.
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if !isCurrent {
                                Button(role: .destructive) {
                                    HapticFeedback.impact(.medium)
                                    store.remove(userId: account.userId)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                Section {
                    Button {
                        dismiss()
                        Task { try? await Task.sleep(for: .milliseconds(350)); showAddAccount = true }
                    } label: {
                        Label("Add account", systemImage: "plus.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }

                if let err = switchError {
                    Section {
                        Text(LocalizedStringKey(err))
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Accounts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheetGround()
    }

    private func switchTo(_ account: SavedAccount) async {
        isSwitching = true
        switchError = nil
        do {
            try await auth.switchTo(account: account)
            dismiss()
        } catch {
            // An auth-layer rejection means the server no longer accepts this
            // refresh token (logged out elsewhere, revoked, or saved before
            // build 945's logout cleanup) — it can never switch again, so the
            // stale row self-heals out of the list instead of erroring
            // forever. Network failures keep the account: it may still work.
            if error is AuthError {
                store.remove(userId: account.userId)
                switchError = "That session has expired, so the account was removed from the list. Sign in again to add it back."
            } else {
                switchError = "Could not switch account. Please sign in again."
            }
        }
        isSwitching = false
    }
}

private struct AccountRow: View {
    let account: SavedAccount
    let isCurrent: Bool
    let isSwitching: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                AvatarCircle(account: account)

                VStack(alignment: .leading, spacing: 2) {
                    if let name = account.displayName, !name.isEmpty {
                        Text(name)
                            .font(AppFont.subheadline)
                            .foregroundStyle(.primary)
                    }
                    Text(account.email)
                        .font(AppFont.scaled(13))
                        .foregroundStyle(Color.primary.opacity(0.55))
                }

                Spacer()

                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(AppFont.scaled(18))
                } else if isSwitching {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isCurrent || isSwitching)
    }
}

private struct AvatarCircle: View {
    let account: SavedAccount

    var body: some View {
        Group {
            if let urlStr = account.avatarUrl, let url = URL(string: urlStr) {
                StorageImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                    } else {
                        initialView
                    }
                }
            } else {
                initialView
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
    }

    private var initialView: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(account.initial)
                .font(AppFont.scaled(16, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}
