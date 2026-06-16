import SwiftUI
import PhotosUI

// MARK: - PropertyDetailView sections

extension PropertyDetailView {

    @ViewBuilder
    func mainContent(_ property: PropertyModel) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                photoHeader(property)

                VStack(spacing: 16) {
                    PageHeader(
                        title: property.name,
                        subtitle: property.propertyType.uppercased()
                    )

                    basicCard(property)

                    if let story = property.story, !story.isEmpty {
                        storyCard(story)
                    }

                    if let renovations = property.renovations, !renovations.isEmpty {
                        renovationsCard(renovations)
                    }

                    if let owners = property.owners, !owners.isEmpty {
                        ownersCard(owners)
                    }

                    plansButton

                    Spacer(minLength: 110)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
        }
        .background(appBackground.ignoresSafeArea())
    }

    // MARK: Photo header

    @ViewBuilder
    private func photoHeader(_ property: PropertyModel) -> some View {
        ZStack(alignment: .bottomTrailing) {
            if let urlStr = property.photoUrl, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        photoPlaceholder
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 280)
                .clipped()
            } else {
                photoPlaceholder
                    .frame(maxWidth: .infinity)
                    .frame(height: 280)
            }

            LinearGradient(
                colors: [.clear, Color(uiColor: .systemBackground).opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 120)
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)

            Group {
                if isUploadingPhoto {
                    ProgressView()
                        .tint(.white)
                        .padding(12)
                        .glassCircle()
                } else {
                    Button { showPhotoMenu = true } label: {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(12)
                    }
                    .buttonStyle(.plain)
                    .glassCircle()
                }
            }
            .padding(16)
        }
        .frame(height: 280)
    }

    private var photoPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [.blue.opacity(0.65), .indigo.opacity(0.5), .purple.opacity(0.4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "house.fill")
                .font(.system(size: 72, weight: .semibold))
                .foregroundStyle(.white.opacity(0.25))
        }
    }

    // MARK: Basic details card

    private func basicCard(_ property: PropertyModel) -> some View {
        GlassCard(padding: 0) {
            VStack(spacing: 0) {
                row("mappin.fill", "Address", "\(property.addressLine1), \(property.city)", .blue)
                rowDivider()
                if !property.country.isEmpty {
                    row("globe.europe.africa.fill", "Country", property.country, .blue)
                    rowDivider()
                }
                if let size = property.sizeSqm {
                    row("ruler.fill", "Area", "\(Int(size)) m²", .orange)
                    rowDivider()
                }
                if let rooms = property.numRooms {
                    row("door.left.hand.open", "Rooms", "\(rooms)", .green)
                    rowDivider()
                }
                if let year = property.yearBuilt {
                    row("calendar.badge.clock", "Year built", "\(year)", .indigo)
                    rowDivider()
                }
                if let score = property.healthScore {
                    row("heart.fill", "Health score", "\(score)/100",
                        score >= 70 ? .green : score >= 40 ? .orange : .red)
                    rowDivider()
                }
                if let lat = property.latitude, let lon = property.longitude {
                    row("location.fill", "Coordinates",
                        String(format: "%.4f, %.4f", lat, lon), .teal)
                }
            }
        }
    }

    private func row(_ icon: String, _ label: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color.opacity(0.14))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
            }
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(Color.primary.opacity(0.5))
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func rowDivider() -> some View {
        Rectangle()
            .fill(Color.primary.opacity(0.05))
            .frame(height: 0.5)
            .padding(.leading, 58)
    }

    // MARK: Story

    private func storyCard(_ story: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Story", systemImage: "text.quote")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.8)
                Text(story)
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Renovations timeline

    private func renovationsCard(_ renovations: [Renovation]) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("Renovations", systemImage: "wrench.and.screwdriver.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.8)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(renovations.enumerated()), id: \.element.id) { idx, r in
                        HStack(alignment: .top, spacing: 14) {
                            VStack(spacing: 0) {
                                Circle()
                                    .fill(.blue)
                                    .frame(width: 10, height: 10)
                                    .padding(.top, 4)
                                if idx < renovations.count - 1 {
                                    Rectangle()
                                        .fill(Color.accentColor.opacity(0.2))
                                        .frame(width: 2, height: 32)
                                }
                            }
                            .frame(width: 10)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(r.title)
                                    .font(.system(size: 14, weight: .semibold))
                                Text(r.yearRange)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.bottom, idx < renovations.count - 1 ? 22 : 0)

                            Spacer()
                        }
                    }
                }
            }
        }
    }

    // MARK: Owners history

    private func ownersCard(_ owners: [OwnerRecord]) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("Owners", systemImage: "person.2.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.8)

                VStack(spacing: 0) {
                    ForEach(Array(owners.enumerated()), id: \.element.id) { idx, owner in
                        VStack(spacing: 0) {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(Color.primary.opacity(0.08))
                                        .frame(width: 36, height: 36)
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color.primary.opacity(0.45))
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(owner.name)
                                        .font(.system(size: 14, weight: .semibold))
                                    Text(owner.yearRange)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 8)
                            if idx < owners.count - 1 {
                                Rectangle()
                                    .fill(Color.primary.opacity(0.05))
                                    .frame(height: 0.5)
                                    .padding(.leading, 48)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Plans

    private var plansButton: some View {
        NavigationLink {
            BlueprintsView()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "doc.richtext.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.orange)
                }
                Text("Property plans")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.28))
            }
            .padding(16)
        }
        .buttonStyle(.plain)
        .liquidGlass(cornerRadius: 18)
    }
}

// MARK: - Camera picker

struct PropertyCameraPickerView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: PropertyCameraPickerView
        init(_ parent: PropertyCameraPickerView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onCapture(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
