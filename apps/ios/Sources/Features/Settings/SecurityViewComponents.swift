import SwiftUI
import Supabase

// MARK: - Active Sessions Sheet

struct ActiveSessionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthService

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        sessionRow(
                            icon: "iphone",
                            title: "This device",
                            subtitle: "Current session · active now",
                            color: Color(red: 0.3, green: 0.82, blue: 0.45),
                            isCurrent: true
                        )
                    }
                    .liquidGlass(cornerRadius: 20)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                    Text("You can sign out other sessions if you notice suspicious activity.")
                        .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.38))
                        .multilineTextAlignment(.center).padding(.horizontal, 28).padding(.top, 16)

                    Button {
                        Task { try? await supabase.auth.signOut(scope: .others) }
                    } label: {
                        Text("Sign out all other sessions")
                            .font(AppFont.footnoteEmphasis).foregroundStyle(.red)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20).padding(.top, 20)
                }
            }
            .navigationTitle("Active sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(.blue)
                }
            }
        }
    }

    private func sessionRow(icon: String, title: LocalizedStringKey, subtitle: LocalizedStringKey, color: Color, isCurrent: Bool) -> some View {
        HStack(spacing: 12) {
            ColoredIconBadge(icon: icon, color: color)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 15)).foregroundStyle(.primary)
                    if isCurrent {
                        Text("CURRENT")
                            .font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(color, in: Capsule())
                    }
                }
                Text(subtitle).font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.4))
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
    }
}

// MARK: - Export Item

struct ExportItem: Identifiable {
    let id = UUID()
    let url: URL
}
