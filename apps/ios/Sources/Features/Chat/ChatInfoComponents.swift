// Shared building blocks of the chat info screens (split from ChatInfoViews).
import SwiftUI
import UIKit
import PhotosUI
import LocalAuthentication
import AudioToolbox
import AVFoundation

struct EditTextSheet: View {
    let title: String
    @State var text: String
    var note: String? = nil
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topLeading) {
                Color.clear
                VStack(alignment: .leading, spacing: 12) {
                    TextEditor(text: $text)
                        .focused($focused)
                        .font(AppFont.scaled(16))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 90, maxHeight: 200)
                        .padding(.horizontal, AppSpacing.sm)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: AppRadius.md))
                    if let note {
                        Text(note)
                            .font(AppFont.scaled(13)).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    }
                    Spacer()
                }
                .padding(AppSpacing.lg)
            }
            .navigationTitle(LocalizedStringKey(title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvează") { onSave(text.trimmingCharacters(in: .whitespacesAndNewlines)); dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
        .presentationBackground(.thinMaterial)
    }
}

// MARK: - Shared info bits

struct InfoActionCard: View {
    let label: String
    let icon: String
    let action: () -> Void
    var body: some View {
        Button {
            HapticFeedback.impact(.light)
            action()
        } label: {
            VStack(spacing: 7) {
                // Liquid Glass circular action button (iOS Contacts idiom).
                Image(systemName: icon)
                    .font(AppFont.scaled(19, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 52, height: 52)
                    .glassCircle()
                Text(LocalizedStringKey(label))
                    .font(AppFont.caption2)
                    .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(LocalizedStringKey(label)))
    }
}

/// Uppercase-captioned glass card section — the ChatSettingsView grouping
/// idiom, adapted for the chat info pages (which manage their own gutters).
struct InfoSection<Content: View>: View {
    var title: LocalizedStringKey? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .textCase(.uppercase)
                    .font(AppFont.captionStrong)
                    .foregroundStyle(.secondary)
                    .padding(.leading, AppSpacing.sm)
            }
            VStack(spacing: 0) { content }
                .liquidGlass(cornerRadius: AppRadius.lg)
        }
        .padding(.horizontal, AppSpacing.lg)
    }
}

/// Circular member avatar with the chat-thread resolution order: directory
/// photo (or contact photo URL) via StorageImage, initials fallback — never
/// a blank circle.
struct MemberPhotoAvatar: View {
    let color: Color
    let initials: String
    let avatarURL: URL?
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.18))
            if let avatarURL {
                StorageImage(url: avatarURL) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                    } else {
                        initialsText
                    }
                }
            } else {
                initialsText
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initialsText: some View {
        Text(initials)
            .font(AppFont.scaled(size * 0.36, weight: .bold))
            .foregroundStyle(color)
    }
}

/// Small pill shown on settings rows that only group admins can change.
struct AdminBadge: View {
    var body: some View {
        Text("Admin")
            .font(AppFont.label)
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, AppSpacing.sm).padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.14), in: Capsule())
    }
}

struct InfoRow: View {
    let icon: String
    let label: String
    var value: String? = nil
    var tint: Color = .primary
    var showChevron: Bool = true
    var adminBadge: Bool = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(AppFont.scaled(17))
                    .foregroundStyle(tint == .primary ? Color.primary.opacity(AppOpacity.emphasis) : tint)
                    .frame(width: 26)
                Text(LocalizedStringKey(label))
                    .foregroundStyle(tint)
                Spacer()
                if let value {
                    Text(value).foregroundStyle(Color.primary.opacity(0.38))
                }
                if adminBadge { AdminBadge() }
                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(AppFont.captionEmphasis)
                        .foregroundStyle(Color.primary.opacity(0.25))
                }
            }
            .font(AppFont.scaled(16))
            .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.base)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The visual content of an InfoRow without the Button — for use inside a NavigationLink.
struct InfoRowLabel: View {
    let icon: String
    let label: String
    var value: String? = nil
    var adminBadge: Bool = false
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(AppFont.scaled(17))
                .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                .frame(width: 26)
            Text(LocalizedStringKey(label))
                .foregroundStyle(.primary)
            Spacer()
            if let value {
                Text(value).foregroundStyle(Color.primary.opacity(0.38))
            }
            if adminBadge { AdminBadge() }
            Image(systemName: "chevron.right")
                .font(AppFont.captionEmphasis)
                .foregroundStyle(Color.primary.opacity(0.25))
        }
        .font(AppFont.scaled(16))
        .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.base)
        .contentShape(Rectangle())
    }
}

/// Toggle row that locks + hides a conversation on this device (WhatsApp-style).
struct SecureChatToggle: View {
    let convId: String
    @State private var secured = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(AppFont.scaled(16)).foregroundStyle(Color.primary.opacity(AppOpacity.emphasis)).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text("Secure conversation").font(AppFont.scaled(16))
                Text("Lock and hide this chat on this device.")
                    .font(AppFont.scaled(12)).foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
            }
            Spacer()
            Toggle("", isOn: $secured).labelsHidden()
        }
        .padding(.horizontal, AppSpacing.lg).padding(.vertical, 10)
        .onAppear { secured = ChatLockStore.isLocked(convId) }
        .onChange(of: secured) { _, on in ChatLockStore.setLocked(convId, on) }
    }
}

// MARK: - Large avatars

struct GroupChatAvatarLarge: View {
    let members: [FamilyMember]
    var photoUrl: String?
    var body: some View {
        ZStack {
            if let urlStr = photoUrl, let url = URL(string: urlStr) {
                StorageImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill().clipShape(Circle())
                    } else { placeholder }
                }
            } else { placeholder }
        }
        .clipShape(Circle())
    }
    private var placeholder: some View {
        ZStack {
            Circle().fill(Color.accentColor.opacity(0.15))
            Image(systemName: "person.2.fill")
                .font(AppFont.scaled(40))
                .foregroundStyle(Color.accentColor)
        }
    }
}
