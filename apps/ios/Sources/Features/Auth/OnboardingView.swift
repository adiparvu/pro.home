import SwiftUI
import Supabase

struct OnboardingView: View {
    @AppStorage("prvio.onboarding.done") private var onboardingDone = false
    @EnvironmentObject private var propertyService: PropertyService
    @EnvironmentObject private var zoneService: PropertyZoneService
    @EnvironmentObject private var auth: AuthService

    @State private var step = 0
    @State private var propertyName = ""
    @State private var propertyAddress = ""
    @State private var propertyType = "apartment"
    @State private var isSaving = false
    @State private var saveError: String? = nil

    private let types = ["apartment", "house", "villa", "studio", "commercial"]

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                progressBar
                    .padding(.top, 16)
                    .padding(.horizontal, 32)

                TabView(selection: $step) {
                    WelcomeStep().tag(0)
                    PropertyStep(
                        name: $propertyName,
                        address: $propertyAddress,
                        type: $propertyType,
                        types: types
                    ).tag(1)
                    FeaturesStep().tag(2)
                    ReadyStep().tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: step)

                navigationButtons
                    .padding(.horizontal, 32)
                    .padding(.bottom, 44)
            }
        }
        .alert("Something went wrong", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK") { saveError = nil }
        } message: {
            if let err = saveError { Text(err) }
        }
    }

    // MARK: - Progress

    private var progressBar: some View {
        HStack(spacing: 6) {
            ForEach(0..<4) { i in
                Capsule()
                    .fill(i <= step ? Color.white : Color.primary.opacity(0.15))
                    .frame(height: 3)
                    .animation(.spring(response: 0.3), value: step)
            }
        }
    }

    // MARK: - Nav buttons

    private var navigationButtons: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button {
                    HapticFeedback.impact(.light)
                    withAnimation { step -= 1 }
                } label: {
                    Text("Back")
                        .font(AppFont.body)
                        .foregroundStyle(Color.primary.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Button {
                if step < 3 {
                    HapticFeedback.impact(.medium)
                    withAnimation { step += 1 }
                } else {
                    Task { await finish() }
                }
            } label: {
                if isSaving {
                    ProgressView().tint(.white).frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(.blue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    Text(LocalizedStringKey(step == 3 ? "Get Started" : (step == 1 && propertyName.isEmpty ? "Skip" : "Continue")))
                        .font(AppFont.subheadline)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            LinearGradient(colors: step == 3 ? [.blue, .purple] : [Color.primary.opacity(0.15), Color.primary.opacity(0.15)],
                                           startPoint: .leading, endPoint: .trailing),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                }
            }
            .buttonStyle(.plain)
            .disabled(isSaving)
        }
    }

    private func finish() async {
        isSaving = true

        // Save property if name entered
        if !propertyName.isEmpty, let uid = auth.session?.user.id {
            struct NewProperty: Encodable {
                let userId: UUID
                let name: String
                let address: String
                let type: String
                let createdAt: String
                enum CodingKeys: String, CodingKey {
                    case name, address, type
                    case userId = "user_id"
                    case createdAt = "created_at"
                }
            }
            struct InsertedProperty: Decodable { let id: UUID }
            // Capture the inserted ID directly from the response so zone creation
            // doesn't depend on load() timing / RLS propagation race.
            var newPropertyId: UUID?
            do {
                let resp: PostgrestResponse<InsertedProperty> = try await supabase
                    .from("properties")
                    .insert(NewProperty(
                        userId: uid,
                        name: propertyName,
                        address: propertyAddress,
                        type: propertyType,
                        createdAt: ISO8601DateFormatter().string(from: Date())
                    ))
                    .select("id")
                    .single()
                    .execute()
                newPropertyId = resp.value.id
            } catch {
                #if DEBUG
                print("[Onboarding] property insert error: \(error)")
                #endif
                saveError = error.localizedDescription
            }
            await propertyService.load()

            // Generate default zones for the new property's type
            if let propertyId = newPropertyId ?? propertyService.primary?.id {
                let now = ISO8601DateFormatter().string(from: Date())
                let templates = PropertyTypeZones.templates(for: propertyType)
                for (index, template) in templates.enumerated() {
                    let payload = NewPropertyZone(
                        propertyId: propertyId,
                        name: template.name,
                        icon: template.icon,
                        colorHex: template.colorHex,
                        layer: PropertyLayer.property.rawValue,
                        healthScore: 100,
                        polygon: [],
                        sortOrder: index,
                        createdAt: now,
                        updatedAt: now
                    )
                    await zoneService.add(payload)
                }
            }
        }

        HapticFeedback.success()
        isSaving = false
        onboardingDone = true
    }
}

// MARK: - Steps

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.blue.opacity(0.3), .purple.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 120, height: 120)
                Image(systemName: "house.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.primary)
            }
            VStack(spacing: 12) {
                Text("Welcome to PRVIO")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                Text("Your all-in-one property management companion. Let's get you set up in 3 quick steps.")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.primary.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}

private struct PropertyStep: View {
    @Binding var name: String
    @Binding var address: String
    @Binding var type: String
    let types: [String]

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 8) {
                Text("Your Property")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.primary)
                Text("Tell us a bit about your property.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.primary.opacity(0.5))
            }

            VStack(spacing: 0) {
                fieldRow(icon: "house.fill", placeholder: "Property name (e.g. Main Apartment)", text: $name)
                Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 52)
                fieldRow(icon: "mappin.circle.fill", placeholder: "Address (optional)", text: $address)
            }
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(types, id: \.self) { t in
                        Button {
                            HapticFeedback.selection()
                            type = t
                        } label: {
                            Text(LocalizedStringKey(t.capitalized))
                                .font(.system(size: 13, weight: type == t ? .semibold : .regular))
                                .foregroundStyle(type == t ? Color.black : Color.primary.opacity(0.6))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(type == t ? Color.white : Color.primary.opacity(0.08), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private func fieldRow(icon: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(.blue)
                .frame(width: 28)
            TextField(placeholder, text: text)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .tint(.accentColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct FeaturesStep: View {
    let features: [(icon: String, color: Color, title: String, desc: String)] = [
        ("checklist",          .blue,                           "Task Manager",   "Track maintenance and repairs"),
        ("chart.bar.xaxis",    Color(red: 0.3, green: 0.85, blue: 0.5), "Analytics", "Monitor finances & performance"),
        ("doc.text.fill",      .orange,                         "Documents",      "Store warranties & certificates"),
        ("sparkles",           .purple,                         "ARIA Assistant", "AI powered property advisor"),
    ]

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 8) {
                Text("Everything You Need")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.primary)
                Text("Packed with smart features to manage your property effortlessly.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.primary.opacity(0.5))
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                ForEach(features, id: \.title) { f in
                    HStack(spacing: 14) {
                        ColoredIconBadge(icon: f.icon, color: f.color, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(LocalizedStringKey(f.title)).font(AppFont.subheadline).foregroundStyle(.primary)
                            Text(LocalizedStringKey(f.desc)).font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.45))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
                }
            }
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}

private struct ReadyStep: View {
    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color(red: 0.3, green: 0.85, blue: 0.5).opacity(0.3), .blue.opacity(0.3)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 120, height: 120)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.primary)
            }
            VStack(spacing: 12) {
                Text("You're All Set!")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.primary)
                Text("PRVIO is ready to help you manage your property smarter.")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.primary.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}
