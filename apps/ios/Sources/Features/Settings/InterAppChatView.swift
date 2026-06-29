import SwiftUI

// MARK: - Cross-app messaging (UI shell)
//
// Replicates WhatsApp's "Conversații inter-aplicații" settings screen. This is
// a visual + preference shell — actually receiving messages from third-party
// apps needs an interoperability gateway on the backend, which doesn't exist
// yet. The toggles persist the user's choice so the wiring is ready.

struct InterAppChatView: View {
    @AppStorage("prvio.interop.enabled")  private var enabled  = false
    @AppStorage("prvio.interop.requests") private var requests = true
    @State private var showAbout = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 22) {
                PageHeader(title: "Conversații inter-aplicații")

                // Enable
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $enabled.animation()) {
                        Text("Activează")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .liquidGlass(cornerRadius: 16)

                    Text("Permite să ți se trimită mesaje pe PRV HOUSE din aplicațiile terțe selectate.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.primary.opacity(0.5))
                        .padding(.horizontal, 6)
                }

                if enabled {
                    // Requests
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: $requests) {
                            Text("Solicitări din aplicații terțe")
                                .font(.system(size: 16))
                                .foregroundStyle(.primary)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 14)
                        .liquidGlass(cornerRadius: 16)

                        Text("Primești notificare când cineva vrea să-ți trimită mesaj din altă aplicație.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.primary.opacity(0.5))
                            .padding(.horizontal, 6)
                    }
                }

                // About
                Button { showAbout = true } label: {
                    HStack {
                        Text("Despre conversațiile inter-aplicații")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.accentColor)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.accentColor.opacity(0.5))
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .liquidGlass(cornerRadius: 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Text("Mesageria între aplicații este în pregătire — necesită un serviciu de interoperabilitate. Preferințele tale sunt salvate de pe acum.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.primary.opacity(0.35))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)

                Spacer(minLength: 60)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAbout) { aboutSheet }
    }

    private var aboutSheet: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "arrow.left.arrow.right.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 12)

                    Text("Ce sunt conversațiile inter-aplicații")
                        .font(.system(size: 20, weight: .bold))

                    Text("Conversațiile inter-aplicații îți permit să primești și să trimiți mesaje către persoane care folosesc alte aplicații de mesagerie compatibile, fără să părăsești PRV HOUSE.")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.primary.opacity(0.7))

                    aboutPoint("lock.fill", "Criptare", "Mesajele rămân criptate de la un capăt la altul atunci când aplicația terță acceptă acest lucru.")
                    aboutPoint("bell.badge.fill", "Control", "Primești o solicitare înainte ca cineva dintr-o altă aplicație să-ți poată scrie.")
                    aboutPoint("hand.raised.fill", "Confidențialitate", "Poți dezactiva oricând mesageria între aplicații din acest ecran.")

                    Spacer(minLength: 40)
                }
                .padding(20)
            }
            .background(appBackground.ignoresSafeArea())
            .navigationTitle("Despre")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Gata") { showAbout = false } } }
        }
    }

    private func aboutPoint(_ icon: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(body).font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.6))
            }
        }
    }
}
