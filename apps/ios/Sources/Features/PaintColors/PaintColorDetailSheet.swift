import SwiftUI

// MARK: - Paint color page (IMG_8628)
//
// Every saved color gets its own page: the swatch as hero, every REAL
// field (room, surface, brand, code, finish, hex, added / last used
// dates, the leftover-can note, free notes, the label photo), a one-tap
// "Used today" stamp, and the four actions — edit, share, print, delete.
// Rows render only when their data exists; nothing is ever invented.
struct PaintColorDetailSheet: View {
    let colorId: UUID
    @Environment(PaintColorService.self) private var service
    @Environment(\.dismiss) private var dismiss
    @State private var showEdit = false
    @State private var confirmDelete = false
    @State private var photoPreview = false

    /// Live row — edits made in the sheet propagate the moment they land.
    private var color: PaintColor? {
        service.colors.first { $0.id == colorId }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                if let color {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: AppSpacing.xl) {
                            hero(color)
                            detailsCard(color)
                            usageCard(color)
                            if let notes = color.notes, !notes.isEmpty {
                                notesCard(notes)
                            }
                            actionsRow(color)
                            deleteButton
                            Spacer(minLength: AppSpacing.xxl)
                        }
                        .padding(.horizontal, AppSpacing.xl)
                        .padding(.top, AppSpacing.sm)
                    }
                }
            }
            .navigationTitle(color?.colorName ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(.primary)
                }
            }
            .sheet(isPresented: $showEdit) {
                if let color { AddPaintColorSheet(editing: color) }
            }
            .confirmationDialog("paint_delete_confirm", isPresented: $confirmDelete,
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let color {
                        Task { await service.delete(color); dismiss() }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    // MARK: Hero — the color itself

    private func hero(_ color: PaintColor) -> some View {
        VStack(spacing: AppSpacing.md) {
            RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                .fill(color.swatchColor)
                .frame(height: 132)
                .overlay(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                    .strokeBorder(Color.hairline, lineWidth: 1))
            VStack(spacing: AppSpacing.xxs) {
                Text(verbatim: color.colorName)
                    .font(AppFont.title3)
                    .foregroundStyle(.primary)
                HStack(spacing: AppSpacing.xs) {
                    if let code = color.code, !code.isEmpty { chip(Text(verbatim: code)) }
                    if let finish = color.finish { chip(Text(verbatim: finish.displayName)) }
                    if let brand = color.brand, !brand.isEmpty { chip(Text(verbatim: brand)) }
                }
            }
        }
    }

    private func chip(_ text: Text) -> some View {
        text.font(AppFont.label)
            .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Color.subtleFill, in: Capsule())
    }

    // MARK: Details — only real fields

    private func detailsCard(_ color: PaintColor) -> some View {
        GlassCard(padding: 0) {
            VStack(spacing: 0) {
                row("door.left.hand.closed", "Room", color.roomName, .blue)
                div
                row("square.split.bottomrightquarter", "paint_surface",
                    surfaceLabel(color.surface), .brandPurple)
                if let hex = color.hexColor, !hex.isEmpty {
                    div
                    row("number", "paint_hex", hex.uppercased(), .orange)
                }
                if let added = AppDate.date(from: color.createdAt) ?? AppDate.day(from: color.createdAt) {
                    div
                    row("calendar", "paint_added",
                        added.formatted(date: .abbreviated, time: .omitted), Color.brandSuccess)
                }
                if let photo = color.photoUrl, !photo.isEmpty {
                    div
                    Button { photoPreview = true } label: {
                        row("photo.fill", "paint_photo_view", "", .teal, chevron: true)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $photoPreview) {
            if let urlStr = color.photoUrl, let url = URL(string: urlStr) {
                StorageImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFit()
                    } else { ProgressView() }
                }
                .presentationDetents([.large])
                .presentationBackground(.black)
            }
        }
    }

    private func surfaceLabel(_ raw: String) -> String {
        // The form's fixed surface catalog — unknown values show as-is.
        let key = "paint_surface_\(raw)"
        let localized = String(localized: String.LocalizationValue(key))
        return localized == key ? raw : localized
    }

    // MARK: Usage — last used + leftover can (migration 165)

    private func usageCard(_ color: PaintColor) -> some View {
        GlassCard(padding: 0) {
            VStack(spacing: 0) {
                if let raw = color.lastUsedAt, let day = AppDate.day(from: raw) {
                    row("paintbrush.pointed.fill", "paint_last_used",
                        day.formatted(date: .abbreviated, time: .omitted), .pink)
                } else {
                    row("paintbrush.pointed.fill", "paint_last_used",
                        String(localized: "paint_never_used"), .pink)
                }
                div
                // One honest tap keeps the date true without opening the form.
                Button {
                    var updated = color
                    updated.lastUsedAt = AppDate.dayString(from: Date())
                    Task { await service.update(updated); HapticFeedback.success() }
                } label: {
                    row("checkmark.circle.fill", "paint_used_today", "", Color.accentColor)
                }
                .buttonStyle(.plain)
                div
                if let leftover = color.leftoverNote, !leftover.isEmpty {
                    row("shippingbox.fill", "paint_leftover", leftover, .brown)
                } else {
                    row("shippingbox.fill", "paint_leftover",
                        String(localized: "paint_no_leftover"), .brown)
                }
            }
        }
    }

    private func notesCard(_ notes: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("Notes")
                    .font(AppFont.captionStrong)
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                Text(verbatim: notes)
                    .font(AppFont.scaled(14))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Actions

    private func actionsRow(_ color: PaintColor) -> some View {
        HStack(spacing: AppSpacing.sm) {
            actionButton("pencil", "Edit") { showEdit = true }
            actionButton("square.and.arrow.up", "Share") {
                if let image = PaintColorCard.render(color) {
                    SystemActions.share([image])
                }
            }
            actionButton("printer.fill", "Print") {
                if let image = PaintColorCard.render(color) {
                    SystemActions.print(image: image, jobName: color.colorName)
                }
            }
        }
    }

    private func actionButton(_ icon: String, _ label: LocalizedStringKey,
                              action: @escaping () -> Void) -> some View {
        Button {
            HapticFeedback.impact(.light)
            action()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon).font(AppFont.scaled(16, weight: .semibold))
                Text(label).font(AppFont.label)
            }
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.md)
            .glassCapsule()
        }
        .buttonStyle(.plain)
    }

    private var deleteButton: some View {
        Button(role: .destructive) { confirmDelete = true } label: {
            Label("paint_delete", systemImage: "trash")
                .font(AppFont.scaled(15, weight: .semibold))
                .foregroundStyle(Color.brandDanger)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.md)
                .glassCapsule()
        }
        .buttonStyle(.plain)
    }

    // MARK: Shared row bits

    private func row(_ icon: String, _ label: LocalizedStringKey, _ value: String,
                     _ tint: Color, chevron: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(AppFont.scaled(13))
                .foregroundStyle(tint)
                .frame(width: 28)
            Text(label).font(AppFont.scaled(14)).foregroundStyle(.primary)
            Spacer()
            if !value.isEmpty {
                Text(verbatim: value)
                    .font(AppFont.scaled(13))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    .multilineTextAlignment(.trailing)
            }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(11, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, 12)
    }

    private var div: some View {
        Rectangle().fill(Color.hairline).frame(height: 0.5).padding(.leading, 52)
    }
}

// MARK: - The shareable / printable spec card (one color)

enum PaintColorCard {
    /// A clean light-mode card for AirPrint / share — the store slip.
    @MainActor static func render(_ color: PaintColor) -> UIImage? {
        let card = VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(color.swatchColor)
                    .frame(width: 72, height: 72)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.black.opacity(0.1), lineWidth: 1))
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: color.colorName).font(.system(size: 20, weight: .bold))
                    if let code = color.code, !code.isEmpty {
                        Text(verbatim: code).font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    if let brand = color.brand, !brand.isEmpty {
                        Text(verbatim: brand).font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                specLine("paint_card_room", color.roomName)
                if let finish = color.finish { specLine("paint_card_finish", finish.displayName) }
                if let hex = color.hexColor, !hex.isEmpty { specLine("paint_card_hex", hex.uppercased()) }
            }
            Text(verbatim: "PRVIO").font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 360, alignment: .leading)
        .background(Color.white)
        .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        return renderer.uiImage
    }

    private static func specLine(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(.secondary)
            Spacer()
            Text(verbatim: value).font(.system(size: 13, weight: .medium))
        }
    }
}
