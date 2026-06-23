import SwiftUI

struct AccountSwitcherSheet: View {
    @EnvironmentObject private var auth: AuthService
    @ObservedObject private var store = AccountsStore.shared
    @Binding var showAddAccount: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var switchError: String?
    @State private var isSwitching = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.accounts) { account in
                        AccountRow(
                            account: account,
                            isCurrent: account.userId == auth.session?.user.id.uuidString,
                            isSwitching: isSwitching
                        ) {
                            guard account.userId != auth.session?.user.id.uuidString else { return }
                            Task { await switchTo(account) }
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
                        Text(err)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
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
    }

    private func switchTo(_ account: SavedAccount) async {
        isSwitching = true
        switchError = nil
        do {
            try await auth.switchTo(account: account)
            dismiss()
        } catch {
            switchError = "Could not switch account. Please sign in again."
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
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    Text(account.email)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.primary.opacity(0.55))
                }

                Spacer()

                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.system(size: 18))
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
                AsyncImage(url: url) { phase in
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
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}
