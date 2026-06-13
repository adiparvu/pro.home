import SwiftUI
import LocalAuthentication

struct SecurityView: View {
    @EnvironmentObject private var auth: AuthService
    @AppStorage("prvio.biometrics") private var biometricsEnabled = false
    @AppStorage("prvio.lockMode") private var lockModeEnabled = false
    @State private var biometricType: LABiometryType = .none
    @State private var showDeleteConfirm = false
    @State private var showPasswordAlert = false
    @State private var passwordResetSent = false
    @State private var alertMessage = ""
    @State private var showActiveSessions = false
    @State private var exportItem: ExportItem?
    @State private var isExporting = false
    @State private var isDeletingAccount = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                mfaSection
                sessionsSection
                advancedSection
                biometricSection
                dataSection
                Spacer(minLength: 100)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Siguranță și securitate")
        .navigationBarTitleDisplayMode(.large)
        .task { checkBiometrics() }
        .alert(alertMessage, isPresented: $showPasswordAlert) {
            Button("OK", role: .cancel) {}
        }
        .confirmationDialog("Șterge contul", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Șterge permanent", role: .destructive) { Task { await deleteAccount() } }
            Button("Anulează", role: .cancel) {}
        } message: {
            Text("Toate datele tale vor fi șterse definitiv. Această acțiune nu poate fi anulată.")
        }
        .sheet(item: $exportItem) { item in ShareSheet(activityItems: [item.url]) }
        .sheet(isPresented: $showActiveSessions) { ActiveSessionsSheet() }
    }

    // MARK: - MFA

    private var mfaSection: some View {
        secGroup(title: "Autentificare multi-factor (MFA)", footer: "Solicită o verificare de securitate suplimentară la autentificare. Dacă nu reușești să treci de această verificare, vei avea opțiunea de a-ți recupera contul.") {
            secRow(icon: "apps.iphone", color: .indigo, title: "Aplicație de autentificare", value: "Dezactivat") {}
            divider
            secRow(icon: "message.fill", color: Color(red: 0.3, green: 0.82, blue: 0.45), title: "Mesaje text", value: "Dezactivat") {}
        }
    }

    // MARK: - Sessions

    private var sessionsSection: some View {
        secGroup(title: "Sesiuni", footer: "Vezi toate dispozitivele și sesiunile care ți-au accesat contul. Poți verifica sesiunile active, elimina dispozitivele de încredere sau folosi „Deconectează-te de pe toate dispozitivele\u{201D} pentru a încheia toate sesiunile.") {
            Button { showActiveSessions = true } label: {
                HStack(spacing: 12) {
                    ColoredIconBadge(icon: "macbook.and.iphone", color: .blue)
                    Text("Sesiuni active")
                        .font(.system(size: 15)).foregroundStyle(.primary)
                    Spacer()
                    Text("1")
                        .font(.system(size: 14)).foregroundStyle(Color.primary.opacity(0.4))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Color.primary.opacity(0.28))
                }
                .padding(.horizontal, 14).padding(.vertical, 13)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Advanced security

    private var advancedSection: some View {
        secGroup(title: "Securitate avansată") {
            Button {
                Task { await sendPasswordReset() }
            } label: {
                HStack(spacing: 12) {
                    ColoredIconBadge(icon: "key.fill", color: .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Securitate avansată a contului")
                            .font(.system(size: 15)).foregroundStyle(.primary)
                        Text("Schimbă parola sau e-mailul")
                            .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.4))
                    }
                    Spacer()
                    if passwordResetSent {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(Color.primary.opacity(0.28))
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 13)
            }
            .buttonStyle(.plain)

            divider

            HStack(spacing: 12) {
                ColoredIconBadge(icon: "lock.shield.fill", color: .purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mod blocare")
                        .font(.system(size: 15)).foregroundStyle(.primary)
                    Text("Cere metode de conectare mai sigure")
                        .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.4))
                }
                Spacer()
                Toggle("", isOn: $lockModeEnabled)
                    .labelsHidden().tint(.purple)
            }
            .padding(.horizontal, 14).padding(.vertical, 13)
        }
    }

    // MARK: - Biometrics (PRVIO codex)

    private var biometricSection: some View {
        secGroup(title: "PRVIO") {
            if biometricType != .none {
                HStack(spacing: 12) {
                    ColoredIconBadge(
                        icon: biometricType == .faceID ? "faceid" : "touchid",
                        color: Color(red: 0.3, green: 0.82, blue: 0.45)
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(biometricType == .faceID ? "Solicită Face ID" : "Solicită Touch ID")
                            .font(.system(size: 15)).foregroundStyle(.primary)
                        Text("Face ID sau cod de acces pentru a accesa PRVIO")
                            .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.4))
                    }
                    Spacer()
                    Toggle("", isOn: $biometricsEnabled)
                        .labelsHidden().tint(.blue)
                        .onChange(of: biometricsEnabled) { _, newVal in
                            if newVal { Task { await authenticateBiometric() } }
                        }
                }
                .padding(.horizontal, 14).padding(.vertical, 13)

                divider
            }

            HStack(spacing: 12) {
                ColoredIconBadge(icon: "timer", color: .cyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Blocare automată")
                        .font(.system(size: 15)).foregroundStyle(.primary)
                    Text("Se blochează după 5 minute de inactivitate")
                        .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.4))
                }
                Spacer()
                Text("5 min")
                    .font(.system(size: 14)).foregroundStyle(Color.primary.opacity(0.38))
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Color.primary.opacity(0.28))
            }
            .padding(.horizontal, 14).padding(.vertical, 13)
        }
    }

    // MARK: - Data & Privacy

    private var dataSection: some View {
        secGroup(title: "Date & Confidențialitate") {
            Button { exportData() } label: {
                HStack(spacing: 12) {
                    ColoredIconBadge(icon: "square.and.arrow.up.fill", color: .cyan)
                    Text("Exportă datele mele")
                        .font(.system(size: 15)).foregroundStyle(.primary)
                    Spacer()
                    if isExporting {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(Color.primary.opacity(0.28))
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 13)
            }
            .buttonStyle(.plain)

            divider

            Button { showDeleteConfirm = true } label: {
                HStack(spacing: 12) {
                    ColoredIconBadge(icon: "trash.fill", color: .red)
                    Text("Șterge contul")
                        .font(.system(size: 15)).foregroundStyle(.red)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Color.primary.opacity(0.28))
                }
                .padding(.horizontal, 14).padding(.vertical, 13)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private func secGroup<Content: View>(title: String, footer: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.38))
                .padding(.leading, 8)

            VStack(spacing: 0) { content() }
                .background {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(LinearGradient(colors: [.white.opacity(0.14), .clear],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(LinearGradient(colors: [.white.opacity(0.32), .white.opacity(0.06)],
                                                             startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.7)
                        }
                }
                .shadow(color: .black.opacity(0.10), radius: 18, y: 4)

            if let footer {
                Text(footer)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.primary.opacity(0.38))
                    .padding(.horizontal, 8)
                    .padding(.top, 2)
            }
        }
    }

    private func secRow(icon: String, color: Color, title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ColoredIconBadge(icon: icon, color: color)
                Text(title)
                    .font(.system(size: 15)).foregroundStyle(.primary)
                Spacer()
                Text(value)
                    .font(.system(size: 14)).foregroundStyle(Color.primary.opacity(0.38))
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Color.primary.opacity(0.28))
            }
            .padding(.horizontal, 14).padding(.vertical, 13)
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 0.4).padding(.leading, 52)
    }

    // MARK: - Actions

    private func checkBiometrics() {
        let ctx = LAContext(); var err: NSError?
        if ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) {
            biometricType = ctx.biometryType
        }
    }

    private func authenticateBiometric() async {
        let ctx = LAContext()
        let reason = biometricType == .faceID ? "Activează Face ID pentru PRVIO" : "Activează Touch ID pentru PRVIO"
        do {
            let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
            if !ok { biometricsEnabled = false }
        } catch { biometricsEnabled = false }
    }

    private func sendPasswordReset() async {
        guard let email = auth.session?.user.email else { return }
        do {
            try await supabase.auth.resetPasswordForEmail(email)
            passwordResetSent = true
            alertMessage = "Email de resetare trimis la \(email). Verifică inbox-ul."
            showPasswordAlert = true
        } catch {
            alertMessage = "Nu s-a putut trimite emailul. Încearcă din nou."
            showPasswordAlert = true
        }
    }

    private func exportData() {
        guard !isExporting else { return }
        isExporting = true
        Task {
            do {
                let userId = try await supabase.auth.session.user.id
                let tasksData   = (try? await supabase.from("maintenance_tasks").select().execute().data)   ?? Data()
                let recordsData = (try? await supabase.from("financial_records").select().execute().data)   ?? Data()
                let docsData    = (try? await supabase.from("documents").select().execute().data)            ?? Data()
                let tasks     = (try? JSONSerialization.jsonObject(with: tasksData))   as? [[String: Any]] ?? []
                let records   = (try? JSONSerialization.jsonObject(with: recordsData)) as? [[String: Any]] ?? []
                let docs      = (try? JSONSerialization.jsonObject(with: docsData))    as? [[String: Any]] ?? []
                let export: [String: Any] = [
                    "exported_at": ISO8601DateFormatter().string(from: Date()),
                    "user_id": userId.uuidString,
                    "tasks": tasks, "financial_records": records, "documents": docs
                ]
                let data = try JSONSerialization.data(withJSONObject: export, options: .prettyPrinted)
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("prvio_export.json")
                try data.write(to: tmp)
                await MainActor.run { isExporting = false; exportItem = ExportItem(url: tmp) }
            } catch {
                await MainActor.run {
                    isExporting = false
                    alertMessage = "Export eșuat: \(error.localizedDescription)"
                    showPasswordAlert = true
                }
            }
        }
    }

    private func deleteAccount() async {
        isDeletingAccount = true
        do {
            let userId = try await supabase.auth.session.user.id
            for table in ["maintenance_tasks", "financial_records", "documents", "contractors", "profiles"] {
                try? await supabase.from(table).delete().eq("user_id", value: userId.uuidString).execute()
            }
            try? await supabase.auth.signOut()
        } catch { try? await supabase.auth.signOut() }
        isDeletingAccount = false
    }
}

// MARK: - Active Sessions Sheet

private struct ActiveSessionsSheet: View {
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
                            title: "Acest dispozitiv",
                            subtitle: "Sesiune curentă · activă acum",
                            color: Color(red: 0.3, green: 0.82, blue: 0.45),
                            isCurrent: true
                        )
                    }
                    .background {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.32), .white.opacity(0.06)],
                                                                 startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.7)
                            }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                    Text("Poți deconecta alte sesiuni dacă observi activitate suspectă.")
                        .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.38))
                        .multilineTextAlignment(.center).padding(.horizontal, 28).padding(.top, 16)

                    Button {
                        Task { try? await supabase.auth.signOut(scope: .others) }
                    } label: {
                        Text("Deconectează toate celelalte sesiuni")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(.red)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20).padding(.top, 20)
                }
            }
            .navigationTitle("Sesiuni active")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gata") { dismiss() }.foregroundStyle(.blue)
                }
            }
        }
    }

    private func sessionRow(icon: String, title: String, subtitle: String, color: Color, isCurrent: Bool) -> some View {
        HStack(spacing: 12) {
            ColoredIconBadge(icon: icon, color: color)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 15)).foregroundStyle(.primary)
                    if isCurrent {
                        Text("CURENT")
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

// MARK: - Helpers

struct ExportItem: Identifiable {
    let id = UUID()
    let url: URL
}
