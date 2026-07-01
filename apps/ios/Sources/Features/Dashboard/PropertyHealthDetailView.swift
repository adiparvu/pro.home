import SwiftUI

// MARK: - Property Health Detail View
// Full-screen breakdown of the property health score with improvement suggestions

struct PropertyHealthDetailView: View {
    let score: Int
    var maintenancePct: Int
    var utilitiesPct: Int
    var securityPct: Int
    var tasksPct: Int

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {

                // ── Hero score ───────────────────────────────────────────
                heroScoreCard

                // ── Category breakdown ──────────────────────────────────
                categoryBreakdownCard

                // ── Suggestions ─────────────────────────────────────────
                suggestionsCard

                // ── How score works ─────────────────────────────────────
                howItWorksCard

                Spacer(minLength: 100)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Property Health")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .font(AppFont.subheadline)
            }
        }
    }

    // MARK: - Hero Score

    private var heroScoreCard: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.06), lineWidth: 14)
                    .frame(width: 160, height: 160)
                Circle()
                    .trim(from: 0, to: CGFloat(score) / 100)
                    .stroke(
                        AngularGradient(
                            colors: [scoreColor.opacity(0.6), scoreColor],
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 1.1, dampingFraction: 0.82), value: score)
                    .frame(width: 160, height: 160)
                VStack(spacing: 4) {
                    Text("\(score)")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("/ 100")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.primary.opacity(0.4))
                }
            }

            VStack(spacing: 6) {
                Text(scoreLabel)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(scoreColor)
                Text(scoreDescription)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.primary.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(scoreColor.opacity(0.20), lineWidth: 1)
        )
        .shadow(color: scoreColor.opacity(0.18), radius: 20, y: 6)
    }

    // MARK: - Category Breakdown

    private var categoryBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Breakdown")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.primary)

            categoryRow(
                icon: "wrench.and.screwdriver",
                label: "Maintenance",
                detail: maintenanceDetail,
                pct: maintenancePct,
                color: .orange
            )
            Divider().opacity(0.3)
            categoryRow(
                icon: "bolt.fill",
                label: "Utilities",
                detail: utilitiesDetail,
                pct: utilitiesPct,
                color: Color(red: 0.35, green: 0.65, blue: 1.0)
            )
            Divider().opacity(0.3)
            categoryRow(
                icon: "lock.shield.fill",
                label: "Security",
                detail: securityDetail,
                pct: securityPct,
                color: Color(red: 0.48, green: 0.41, blue: 0.93)
            )
            Divider().opacity(0.3)
            categoryRow(
                icon: "checklist",
                label: "Tasks",
                detail: tasksDetail,
                pct: tasksPct,
                color: Color(red: 0.20, green: 0.82, blue: 0.48)
            )
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    private func categoryRow(icon: String, label: String, detail: String, pct: Int, color: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(AppFont.headline)
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(label)
                        .font(AppFont.subheadline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(pct)%")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(pct >= 80 ? color : pct >= 60 ? .orange : .red)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08)).frame(height: 5)
                        Capsule()
                            .fill(LinearGradient(colors: [color.opacity(0.7), color], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * CGFloat(pct) / 100, height: 5)
                    }
                }
                .frame(height: 5)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.primary.opacity(0.45))
            }
        }
    }

    // MARK: - Suggestions

    private var suggestionsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(AppFont.footnoteEmphasis)
                    .foregroundStyle(Color(red: 0.6, green: 0.35, blue: 0.95))
                Text("How to Improve")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.primary)
            }

            ForEach(suggestions, id: \.title) { tip in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: tip.icon)
                        .font(AppFont.footnoteEmphasis)
                        .foregroundStyle(tip.color)
                        .frame(width: 30, height: 30)
                        .background(tip.color.opacity(0.13), in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(tip.title)
                            .font(AppFont.footnoteEmphasis)
                            .foregroundStyle(.primary)
                        Text(tip.body)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.primary.opacity(0.55))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Text("+\(tip.points)pts")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(tip.color)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(tip.color.opacity(0.12), in: Capsule())
                }
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    // MARK: - How it Works

    private var howItWorksCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How the Score Works")
                .font(AppFont.footnoteEmphasis)
                .foregroundStyle(Color.primary.opacity(0.55))
            Text("The property health score is calculated from four categories: Maintenance (30%), Utilities (25%), Security (25%), and Tasks completion (20%). Completing tasks, keeping documents current, and resolving alerts all raise your score.")
                .font(.system(size: 12))
                .foregroundStyle(Color.primary.opacity(0.4))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Computed helpers

    private var scoreColor: Color {
        score >= 80 ? Color(red: 0.20, green: 0.82, blue: 0.48) :
        score >= 55 ? .orange : .red
    }

    private var scoreLabel: String {
        score >= 90 ? "Excelent" :
        score >= 80 ? "Bun" :
        score >= 65 ? "Satisfăcător" :
        score >= 50 ? "Necesită atenție" : "Critică"
    }

    private var scoreDescription: String {
        score >= 80
            ? "Proprietatea ta este bine întreținută. Continuă să rezolvi sarcinile la timp."
            : "Există zone care necesită atenție. Urmărește sugestiile de mai jos pentru a ridica scorul."
    }

    private var maintenanceDetail: String {
        maintenancePct >= 80 ? "Bun — echipamente funcționale" :
        maintenancePct >= 60 ? "Câteva echipamente necesită verificare" :
        "Mai multe echipamente necesită inspecție"
    }

    private var utilitiesDetail: String {
        utilitiesPct >= 80 ? "Facturi la zi, consum normal" :
        utilitiesPct >= 60 ? "Verifică facturile restante" :
        "Facturi neachitate sau consum anormal"
    }

    private var securityDetail: String {
        securityPct >= 80 ? "Sisteme de securitate active" :
        securityPct >= 60 ? "Unele verificări recomandate" :
        "Securitate necesită atenție urgentă"
    }

    private var tasksDetail: String {
        tasksPct >= 90 ? "Toate sarcinile finalizate" :
        tasksPct >= 60 ? "Sarcini active în progres" :
        "Sarcini restante — prioritizează-le"
    }

    private struct Tip {
        let icon: String
        let color: Color
        let title: String
        let body: String
        let points: Int
    }

    private var suggestions: [Tip] {
        var tips: [Tip] = []
        if maintenancePct < 85 {
            tips.append(.init(icon: "wrench.and.screwdriver", color: .orange,
                title: "Verifică echipamentele",
                body: "Adaugă o inspecție anuală la boiler, sistem electric și instalații sanitare.",
                points: 8))
        }
        if utilitiesPct < 90 {
            tips.append(.init(icon: "bolt.fill", color: Color(red: 0.35, green: 0.65, blue: 1.0),
                title: "Actualizează facturile",
                body: "Introduc chitanțele de utilități pentru a menține istoricul complet.",
                points: 5))
        }
        if securityPct < 85 {
            tips.append(.init(icon: "lock.shield.fill", color: Color(red: 0.48, green: 0.41, blue: 0.93),
                title: "Îmbunătățește securitatea",
                body: "Adaugă camere sau senzori în zonele neacoperite ale proprietății.",
                points: 7))
        }
        if tasksPct < 80 {
            tips.append(.init(icon: "checklist", color: Color(red: 0.20, green: 0.82, blue: 0.48),
                title: "Rezolvă sarcinile restante",
                body: "Completează sarcinile scadente — fiecare task finalizat ridică scorul.",
                points: 3))
        }
        if tips.isEmpty {
            tips.append(.init(icon: "star.fill", color: .yellow,
                title: "Proprietate în stare excelentă!",
                body: "Menține ritmul: verificări lunare + documente actualizate + sarcini la zi.",
                points: 0))
        }
        return tips
    }
}
