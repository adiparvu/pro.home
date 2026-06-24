import SwiftUI

/// ARIA insights for the Digital Twin — a quick rule-based summary of the
/// property plus an on-demand AI analysis via the aria-chat edge function.
struct TwinInsightsSheet: View {
    @EnvironmentObject private var propertyService: PropertyService
    @EnvironmentObject private var zoneService: PropertyZoneService
    @EnvironmentObject private var elementService: PropertyElementService
    @EnvironmentObject private var currencyService: CurrencyService
    @EnvironmentObject private var appSettings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var aiReply: String?
    @State private var isThinking = false

    private var zones: [PropertyZone] { zoneService.zones }
    private var objects: [PropertyElement] { elementService.elements }
    private var avgHealth: Int {
        objects.isEmpty ? 100 : objects.reduce(0) { $0 + $1.healthScore } / objects.count
    }
    private var critical: [PropertyElement] { elementService.criticalElements }
    private var totalValue: Double { objects.compactMap { $0.estimatedValue }.reduce(0, +) }

    private var healthColor: Color {
        switch avgHealth {
        case 80...:   return Color(red: 0.2, green: 0.8, blue: 0.45)
        case 50..<80: return .orange
        default:      return .red
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    statsGrid
                    if !critical.isEmpty { criticalCard }
                    aiCard
                }
                .padding(20)
            }
            .background(appBackground.ignoresSafeArea())
            .navigationTitle("ARIA Insights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(
                    LinearGradient(colors: [Color(red: 0.6, green: 0.35, blue: 0.95),
                                            Color(red: 0.35, green: 0.4, blue: 0.95)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Property status")
                    .font(.system(size: 18, weight: .bold))
                Text(propertyService.primary?.name ?? "My property")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            tile("\(zones.count)", "Zones", "square.dashed", .blue)
            tile("\(objects.count)", "Objects", "cube.box.fill", .indigo)
            tile("\(avgHealth)%", "Average health", "heart.fill", healthColor)
            tile(valueString, "Total value", "eurosign.circle.fill", .green)
        }
    }

    private var valueString: String {
        let sym = currencyService.symbol(for: appSettings.preferredCurrency)
        return "\(sym)\(Int(totalValue))"
    }

    private func tile(_ value: String, _ label: LocalizedStringKey, _ icon: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(color)
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(.primary)
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var criticalCard: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Needs attention", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.orange)
                ForEach(critical.prefix(5)) { obj in
                    HStack(spacing: 10) {
                        Image(systemName: obj.elementType.icon)
                            .font(.system(size: 13)).foregroundStyle(obj.healthColor).frame(width: 22)
                        Text(obj.name).font(.system(size: 14)).foregroundStyle(.primary)
                        Spacer()
                        Text("\(obj.healthScore)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(obj.healthColor)
                    }
                }
            }
        }
    }

    private var aiCard: some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Label("ARIA Analysis", systemImage: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0.6, green: 0.35, blue: 0.95))

                if let aiReply {
                    Text(LocalizedStringKey(aiReply))
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if isThinking {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("ARIA is analyzing your property…")
                            .font(.system(size: 14)).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Request an AI analysis based on zones, objects and their condition.")
                        .font(.system(size: 14)).foregroundStyle(.secondary)
                }

                Button {
                    Task { await askARIA() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                        Text(aiReply == nil ? "Ask ARIA" : "Re-analyze")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        LinearGradient(colors: [Color(red: 0.6, green: 0.35, blue: 0.95),
                                                Color(red: 0.35, green: 0.4, blue: 0.95)],
                                       startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isThinking)
            }
        }
    }

    private func askARIA() async {
        isThinking = true
        defer { isThinking = false }
        let criticalNames = critical.prefix(6).map { "\($0.name) (\($0.healthScore)%)" }.joined(separator: ", ")
        let zoneNames = zones.map(\.name).joined(separator: ", ")
        let prompt = """
        You are ARIA, the assistant for the property digital twin. Based on the data below, provide 3–5 short and actionable recommendations in English.
        Zones (\(zones.count)): \(zoneNames.isEmpty ? "none" : zoneNames).
        Objects: \(objects.count). Average health: \(avgHealth)%.
        Objects needing attention: \(criticalNames.isEmpty ? "none" : criticalNames).
        """
        struct ARIAChatPayload: Encodable { let message: String; let property_id: String? }
        struct ARIAResponse: Decodable { let reply: String?; let error: String? }
        do {
            let payload = ARIAChatPayload(message: prompt, property_id: propertyService.primary?.id.uuidString)
            let decoded: ARIAResponse = try await supabase.functions
                .invoke("aria-chat", options: .init(body: payload))
            aiReply = decoded.reply ?? decoded.error ?? "Could not generate an analysis right now."
        } catch {
            aiReply = "Could not reach ARIA. Please try again."
        }
    }
}
