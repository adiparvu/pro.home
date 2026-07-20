import SwiftUI
import PhotosUI

// MARK: - Background (Settings → Aspect → Fundal) — the personalized backdrop
//
// The live weather sky was RETIRED from this page at the owner's request
// (IMG_8767, 2026-07-21) — the backdrop is now a deliberate, quiet choice:
//  · Gradient — a curated static gallery (zero GPU cost);
//  · Fotografia ta — the owner's photo, with a readability dim; text
//    colors follow the photo's measured luminance automatically.
// One live preview up top; the mode's own controls beneath.

struct BackgroundSettingsView: View {
    private var style: BackgroundStyle { .shared }

    @State private var mode = BackgroundStyle.shared.mode
    @State private var gradientId = BackgroundStyle.shared.gradientId
    @State private var photoDim = BackgroundStyle.shared.photoDim
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                previewCard

                SettingsGroup(title: "bg_mode_title") {
                    VStack(spacing: 0) {
                        modeRow(.gradient, icon: "rectangle.fill.badge.checkmark",
                                title: "bg_mode_gradient", caption: "bg_mode_gradient_caption")
                        rowDivider
                        modeRow(.photo, icon: "photo.fill",
                                title: "bg_mode_photo", caption: "bg_mode_photo_caption")
                    }
                }

                switch mode {
                case .gradient, .liveSky: gradientSection
                case .photo:              photoSection
                }

                Spacer(minLength: 100)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle(Text("bg_settings_title"))
        .navigationBarTitleDisplayMode(.large)
        .animation(AppMotion.state, value: mode)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                defer { pickerItem = nil }
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    style.setPhoto(image)
                    mode = .photo
                    HapticFeedback.success()
                }
            }
        }
    }

    // MARK: Live preview — the real chosen backdrop with a sample card

    private var previewCard: some View {
        ZStack {
            AppBackgroundView()
            GlassCard(padding: 16) {
                Text("mood_preview_card_title")
                    .font(AppFont.scaled(15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(AppSpacing.xl)
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: 1)
        )
        .accessibilityHidden(true)
    }

    // MARK: Mode selection

    private func modeRow(_ target: AppBackgroundMode, icon: String,
                         title: LocalizedStringKey, caption: LocalizedStringKey) -> some View {
        let selected = mode == target
        return Button {
            guard mode != target else { return }
            mode = target
            HapticFeedback.impact(.light)
            // Photo mode without a photo yet: the section below opens with
            // its picker, but the REAL backdrop switches only once an
            // image lands (setPhoto) — never a black interim ground.
            if target == .photo && style.photo == nil { return }
            style.mode = target
        } label: {
            HStack(spacing: 12) {
                ColoredIconBadge(icon: icon,
                                 color: selected ? .accentColor : Color.primary.opacity(0.4))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppFont.scaled(15))
                        .foregroundStyle(.primary)
                    Text(caption)
                        .font(AppFont.scaled(12))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(AppFont.scaled(20))
                        .foregroundStyle(Color.accentColor)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                }
            }
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Gradient gallery

    private var gradientSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.md) {
                ForEach(BackgroundGradientPreset.all) { g in
                    gradientTile(g)
                }
            }
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, 2)
        }
    }

    private func gradientTile(_ g: BackgroundGradientPreset) -> some View {
        let selected = gradientId == g.id
        return Button {
            gradientId = g.id
            style.gradientId = g.id
            HapticFeedback.impact(.light)
        } label: {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .fill(LinearGradient(colors: [g.top, g.bottom],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 88, height: 62)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                            .strokeBorder(selected ? Color.accentColor : Color.hairline,
                                          lineWidth: selected ? 2 : 1)
                    )
                Text(LocalizedStringKey(g.titleKey))
                    .font(AppFont.scaled(12, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.accentColor
                                              : Color.primary.opacity(AppOpacity.secondaryText))
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Fotografia ta

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            SettingsGroup(title: "bg_mode_photo") {
                VStack(spacing: 0) {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        HStack(spacing: 12) {
                            ColoredIconBadge(icon: "photo.badge.plus", color: .accentColor)
                            Text(style.photo == nil ? "bg_choose_photo" : "bg_change_photo")
                                .font(AppFont.scaled(15))
                                .foregroundStyle(.primary)
                            Spacer()
                            if let photo = style.photo {
                                Image(uiImage: photo)
                                    .resizable().scaledToFill()
                                    .frame(width: 44, height: 44)
                                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm,
                                                                style: .continuous))
                            }
                        }
                        .padding(.horizontal, AppSpacing.base)
                        .padding(.vertical, 13)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if style.photo != nil {
                        rowDivider
                        VStack(alignment: .leading, spacing: 6) {
                            Text("bg_dim_label")
                                .font(AppFont.scaled(15))
                                .foregroundStyle(.primary)
                            Slider(value: Binding(get: { photoDim },
                                                  set: { photoDim = $0
                                                         style.photoDim = $0 }),
                                   in: 0...0.5)
                                .tint(.accentColor)
                        }
                        .padding(.horizontal, AppSpacing.base)
                        .padding(.vertical, 13)

                        rowDivider
                        Button(role: .destructive) {
                            style.removePhoto()
                            mode = style.mode
                            HapticFeedback.impact(.medium)
                        } label: {
                            HStack(spacing: 12) {
                                ColoredIconBadge(icon: "trash.fill", color: .brandDanger)
                                Text("bg_remove_photo")
                                    .font(AppFont.scaled(15))
                                    .foregroundStyle(Color.brandDanger)
                                Spacer()
                            }
                            .padding(.horizontal, AppSpacing.base)
                            .padding(.vertical, 13)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Text("bg_photo_caption")
                .font(AppFont.scaled(12))
                .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, AppSpacing.sm)
        }
    }

    private var rowDivider: some View {
        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 54)
    }
}
