import SwiftUI

// MARK: - Apple Watch showcase
//
// The Tide-Guide-style presentation of PRVIO's watch app, on the iPhone: a
// paged carousel of hero cards, each with a hand-drawn watch mockup showing
// a REAL screen of our watch app — dashboard, complications, wrist actions,
// shopping & deliveries, zero-setup sync. Everything depicted exists; no
// paywall theatre, just the manual you'd want before raising your wrist.

struct WatchShowcaseView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    private static let pageCount = 5

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                WSPage(mock: AnyView(WSDashboardMock()),
                       title: "ws_p1_title", body: "ws_p1_body").tag(0)
                WSPage(mock: AnyView(WSComplicationsMock()),
                       title: "ws_p2_title", body: "ws_p2_body").tag(1)
                WSPage(mock: AnyView(WSActionsMock()),
                       title: "ws_p3_title", body: "ws_p3_body").tag(2)
                WSPage(mock: AnyView(WSListsMock()),
                       title: "ws_p4_title", body: "ws_p4_body").tag(3)
                WSPage(mock: AnyView(WSSyncMock()),
                       title: "ws_p5_title", body: "ws_p5_body").tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.snappy(duration: 0.3), value: page)

            pageDots
                .padding(.vertical, AppSpacing.base)

            Text("ws_footer")
                .font(.system(size: 12))
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.xxl)
                .padding(.bottom, AppSpacing.lg)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle(Text(verbatim: "Apple Watch"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "Done")) { dismiss() }
            }
        }
    }

    private var pageDots: some View {
        HStack(spacing: 7) {
            ForEach(0..<Self.pageCount, id: \.self) { i in
                Circle()
                    .fill(i == page ? Color.primary : Color.primary.opacity(0.25))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - One carousel page

private struct WSPage: View {
    let mock: AnyView
    let title: LocalizedStringKey
    let body_: LocalizedStringKey

    init(mock: AnyView, title: LocalizedStringKey, body: LocalizedStringKey) {
        self.mock = mock
        self.title = title
        self.body_ = body
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                // Hero card: the watch on a deep gradient, like the reference.
                ZStack {
                    RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                        .fill(LinearGradient(colors: [Color(red: 0.09, green: 0.13, blue: 0.22),
                                                      Color(red: 0.05, green: 0.07, blue: 0.12)],
                                             startPoint: .top, endPoint: .bottom))
                    WatchDeviceFrame { mock }
                        .padding(.vertical, AppSpacing.xl)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 340)

                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text(title)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(body_)
                        .font(.system(size: 16))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, AppSpacing.xxs)

                Spacer(minLength: AppSpacing.lg)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
        }
    }
}

// MARK: - Watch hardware frame (drawn, not a photo)

private struct WatchDeviceFrame<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            band
            ZStack(alignment: .trailing) {
                RoundedRectangle(cornerRadius: 44, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.62), Color(white: 0.38)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 196, height: 232)

                RoundedRectangle(cornerRadius: 38, style: .continuous)
                    .fill(Color.black)
                    .frame(width: 180, height: 216)
                    .overlay(
                        content
                            .frame(width: 164, height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                    )
                    .padding(.trailing, 8)

                // Crown + side button
                VStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(Color(white: 0.55))
                        .frame(width: 5, height: 26)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color(white: 0.5))
                        .frame(width: 4, height: 34)
                }
                .offset(x: 5)
            }
            band
        }
        .accessibilityHidden(true)
    }

    private var band: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.10)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: 96, height: 34)
    }
}

// MARK: - Screen mocks (each depicts the REAL watch app)

/// Page 1: the Today dashboard — health ring, metric cards.
private struct WSDashboardMock: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Gauge(value: 85, in: 0...100) { EmptyView() } currentValueLabel: {
                    Text(verbatim: "85").font(.system(size: 11, weight: .bold, design: .rounded))
                }
                .gaugeStyle(.accessoryCircular)
                .tint(Gradient(colors: [.green.opacity(0.55), .green]))
                .scaleEffect(0.62)
                .frame(width: 34, height: 34)
                Text(verbatim: "PRV Villa")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
            }
            mockGrid
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black)
    }

    private var mockGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 5),
                            GridItem(.flexible(), spacing: 5)], spacing: 5) {
            cell(icon: "checklist", tint: .blue, value: "3")
            cell(icon: "drop.fill", tint: .cyan, value: "2")
            cell(icon: "shippingbox.fill", tint: .indigo, value: "1")
            cell(icon: "cart.fill", tint: .orange, value: "5")
        }
    }

    private func cell(icon: String, tint: Color, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(tint)
            Text(verbatim: value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
        .background(
            LinearGradient(colors: [tint.opacity(0.32), tint.opacity(0.10)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }
}

/// Page 2: a watch face with our accessory complications.
private struct WSComplicationsMock: View {
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                miniGauge(icon: "house.fill", value: "85", tint: .green)
                Text(verbatim: "10:09")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                miniGauge(icon: "checklist", value: "3", tint: .blue)
            }
            // Rectangular complication: tasks with real titles
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 3) {
                    Image(systemName: "checklist")
                        .font(.system(size: 8, weight: .semibold))
                    Text("watch_tasks")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(.white)
                Text(verbatim: "3")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("ws_mock_task")
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(7)
            .background(Color.white.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            HStack(spacing: 10) {
                miniGauge(icon: "drop.fill", value: "2", tint: .cyan)
                miniGauge(icon: "cart.fill", value: "5", tint: .orange)
                miniGauge(icon: "shippingbox.fill", value: "1", tint: .indigo)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private func miniGauge(icon: String, value: String, tint: Color) -> some View {
        Gauge(value: 0.7) {
            Image(systemName: icon).font(.system(size: 7))
        } currentValueLabel: {
            Text(verbatim: value).font(.system(size: 10, weight: .bold, design: .rounded))
        }
        .gaugeStyle(.accessoryCircular)
        .tint(tint)
        .scaleEffect(0.58)
        .frame(width: 32, height: 32)
    }
}

/// Page 3: wrist actions — the act-then-celebrate rows.
private struct WSActionsMock: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("watch_tasks")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            row(icon: "checkmark.circle.fill", tint: .blue, text: "ws_mock_task", done: true)
            row(icon: "circle", tint: .white, text: "ws_mock_task2", done: false)
            Text("watch_plants")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.top, 3)
            row(icon: "drop.fill", tint: .cyan, text: "ws_mock_plant", done: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black)
    }

    private func row(icon: String, tint: Color, text: LocalizedStringKey, done: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: done ? .semibold : .light))
                .foregroundStyle(done ? tint : .white.opacity(0.5))
            Text(text)
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.white.opacity(done ? 0.55 : 1))
                .strikethrough(done, color: .white.opacity(0.4))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7).padding(.vertical, 6)
        .background(
            LinearGradient(colors: [Color.blue.opacity(0.28), Color.blue.opacity(0.08)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }
}

/// Page 4: shopping check-offs and a live parcel.
private struct WSListsMock: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("watch_shopping")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            item("ws_mock_item1", done: true)
            item("ws_mock_item2", done: false)
            Text("watch_deliveries")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "bicycle")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text("ws_mock_parcel")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Text("Out for delivery")
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [Color.indigo.opacity(0.3), Color.indigo.opacity(0.1)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black)
    }

    private func item(_ text: LocalizedStringKey, done: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 11, weight: done ? .semibold : .light))
                .foregroundStyle(done ? .orange : .white.opacity(0.5))
            Text(text)
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.white.opacity(done ? 0.55 : 1))
                .strikethrough(done, color: .white.opacity(0.4))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7).padding(.vertical, 6)
        .background(
            LinearGradient(colors: [Color.orange.opacity(0.28), Color.orange.opacity(0.08)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }
}

/// Page 5: zero-setup sync — the phone pushes, the wrist answers.
private struct WSSyncMock: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                .font(.system(size: 34))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.brandSkyBlue)
            Image(systemName: "arrow.down")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
            Image(systemName: "applewatch.radiowaves.left.and.right")
                .font(.system(size: 30))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}
