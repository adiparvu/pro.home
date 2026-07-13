import SwiftUI
import HomeKit
import Photos

// MARK: - Cameras (HomeKit + RTSP snapshots)
//
// Two honest sources on one pushed page:
// • HomeKit camera accessories — native in-app streaming via HMCameraView.
// • RTSP/IP cameras — still frames polled from their HTTP snapshot endpoint
//   (Hikvision ISAPI / Dahua CGI). Presented explicitly as snapshot preview,
//   never as continuous video.
// Snapshot polling runs only while this page is visible (battery rule).

struct CamerasView: View {
    private let service = CameraService.shared
    private let homeKit = HomeKitService.shared

    @State private var showAddSheet = false
    @State private var editingCamera: SecurityCamera?

    private var gridColumns: [GridItem] {
        [GridItem(.flexible(), spacing: AppSpacing.md),
         GridItem(.flexible(), spacing: AppSpacing.md)]
    }

    var body: some View {
        ZStack {
            // The cameras page sits on the app-wide mood backdrop with
            // adaptive glass chrome. Camera frames themselves are content
            // and stay untinted.
            appBackground.ignoresSafeArea()
            content
        }
        .navigationTitle(Text("cameras_title"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    HapticFeedback.impact(.light)
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(Text("cameras_add"))
            }
        }
        .sheet(isPresented: $showAddSheet) {
            CameraFormSheet(camera: nil)
        }
        .sheet(item: $editingCamera) { camera in
            CameraFormSheet(camera: camera)
        }
        .onAppear {
            // Explicit user navigation to the Cameras page — the sanctioned
            // moment to resolve HMHomeManager (may show the HomeKit prompt).
            homeKit.requestAccess()
            service.startPolling()
        }
        .onDisappear {
            // Also fires when a detail view is pushed on top — the detail
            // runs its own tighter refresh loop, so nothing is lost.
            service.stopPolling()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        let homeKitCameras = homeKit.isAuthorized ? homeKit.cameraAccessories : []
        if service.cameras.isEmpty && homeKitCameras.isEmpty {
            emptyState
        } else {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    Text("cameras_subtitle")
                        .font(AppFont.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, AppSpacing.xxs)

                    if !homeKitCameras.isEmpty {
                        homeKitSection(homeKitCameras)
                    }
                    scenesSection
                    if !service.cameras.isEmpty {
                        rtspSection
                    }
                    Spacer(minLength: 90)
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.sm)
            }
            .refreshable { await service.refreshAll() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.base) {
            EmptyStateView(icon: "video",
                           title: "cameras_empty_title",
                           message: "cameras_empty_message")
            GlassWideButton(icon: "plus", label: "cameras_add") {
                showAddSheet = true
            }
            .padding(.horizontal, AppSpacing.xl)
        }
    }

    // MARK: - HomeKit section

    private func homeKitSection(_ accessories: [HMAccessory]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("cameras_homekit_section")

            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(accessories.enumerated()), id: \.element.uniqueIdentifier) { idx, accessory in
                        NavigationLink {
                            HomeKitCameraDetailView(accessory: accessory)
                        } label: {
                            homeKitRow(accessory)
                        }
                        .buttonStyle(.plain)
                        if idx < accessories.count - 1 {
                            Rectangle().fill(Color.hairline)
                                .frame(height: 0.5).padding(.leading, 60)
                        }
                    }
                }
            }
        }
    }

    private func homeKitRow(_ accessory: HMAccessory) -> some View {
        HStack(spacing: 12) {
            ZStack {
                SmartRadialGlow(diameter: 44, color: .brandSkyBlue)
                Image(systemName: "video.fill")
                    .font(AppFont.footnoteEmphasis)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.brandSkyBlue)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: accessory.name)
                    .font(AppFont.footnote)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("cameras_homekit_live")
                    .font(AppFont.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(AppFont.captionStrong)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, AppSpacing.md)
        .contentShape(Rectangle())
    }

    // MARK: - Scenes

    /// Home × action-set pairs so chips from several homes can share one row
    /// (a struct because ForEach can't key-path into tuple elements).
    private struct ScenePair: Identifiable {
        let home: HMHome
        let actionSet: HMActionSet
        var id: UUID { actionSet.uniqueIdentifier }
    }

    private var scenePairs: [ScenePair] {
        guard homeKit.isAuthorized else { return [] }
        return homeKit.homes.flatMap { home in
            homeKit.actionSets(in: home).map { ScenePair(home: home, actionSet: $0) }
        }
    }

    @ViewBuilder
    private var scenesSection: some View {
        let pairs = scenePairs
        if !pairs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("cameras_scenes_section")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.sm) {
                        ForEach(pairs) { pair in
                            sceneChip(pair.actionSet, in: pair.home)
                        }
                    }
                    .padding(.horizontal, AppSpacing.xxs)
                }
            }
        }
    }

    private func sceneChip(_ actionSet: HMActionSet, in home: HMHome) -> some View {
        Button {
            HapticFeedback.impact(.light)
            Task {
                do {
                    try await homeKit.execute(actionSet, in: home)
                    HapticFeedback.success()
                } catch {
                    HapticFeedback.error()
                    debugLog("Scene execution failed:", error)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(AppFont.captionStrong)
                    .foregroundStyle(Color.accentColor)
                Text(verbatim: actionSet.name)
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, AppSpacing.sm)
            .mediaGlass(in: Capsule(), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: actionSet.name))
    }

    // MARK: - RTSP section

    private var rtspSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("cameras_rtsp_section")

            // The 5s timeline cheaply re-evaluates staleness (>15s → dimmed)
            // even when a failing fetch leaves `latest` untouched.
            TimelineView(.periodic(from: .now, by: 5)) { timeline in
                LazyVGrid(columns: gridColumns, spacing: AppSpacing.md) {
                    ForEach(service.cameras) { camera in
                        NavigationLink {
                            CameraDetailView(camera: camera)
                        } label: {
                            cameraCard(camera, now: timeline.date)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                editingCamera = camera
                            } label: { Label("cameras_edit", systemImage: "pencil") }
                            Button(role: .destructive) {
                                service.delete(camera)
                            } label: { Label("cameras_delete", systemImage: "trash") }
                        }
                    }
                }
            }
        }
    }

    private func cameraCard(_ camera: SecurityCamera, now: Date) -> some View {
        let snap = service.latest[camera.id]
        let isStale = snap.map { now.timeIntervalSince($0.at) > 15 } ?? false

        return Color.clear
            .frame(height: 118)
            .overlay {
                if let snap {
                    Image(uiImage: snap.image)
                        .resizable()
                        .scaledToFill()
                        .opacity(isStale ? 0.45 : 1)
                } else {
                    ZStack {
                        Color.subtleFill
                        VStack(spacing: 6) {
                            ProgressView()
                            Text("cameras_connecting")
                                .font(AppFont.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                if isStale {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(AppFont.captionStrong)
                        .foregroundStyle(Color.brandWarning)
                        .padding(6)
                        .mediaGlass(in: Circle())
                        .padding(AppSpacing.xs)
                        .accessibilityLabel(Text("cameras_stale"))
                }
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: camera.name)
                        .font(AppFont.captionStrong)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let snap {
                        Text(snap.at, style: .relative)
                            .font(AppFont.scaled(10, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, AppSpacing.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(colors: [.black.opacity(0.55), .clear],
                                   startPoint: .bottom, endPoint: .top)
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .strokeBorder(Color.hairline, lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(verbatim: camera.name))
    }

    private func sectionHeader(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(AppFont.label)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .padding(.leading, AppSpacing.xxs)
    }
}

// MARK: - RTSP camera detail (auto-refreshing snapshot)

struct CameraDetailView: View {
    let camera: SecurityCamera

    private let service = CameraService.shared

    @State private var image: UIImage?
    @State private var fillsFrame = false
    @State private var saveFeedback: SaveFeedback?
    @State private var isSaving = false

    private enum SaveFeedback { case saved, denied }

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    snapshotArea

                    Text("cameras_detail_hint")
                        .font(AppFont.caption)
                        .foregroundStyle(.secondary)

                    GlassWideButton(icon: "square.and.arrow.down",
                                    label: "cameras_save_snapshot",
                                    isBusy: isSaving) {
                        saveToPhotos()
                    }
                    .disabled(image == nil)

                    if let saveFeedback {
                        Text(saveFeedback == .saved ? "cameras_saved_to_photos" : "cameras_photos_denied")
                            .font(AppFont.caption)
                            .foregroundStyle(saveFeedback == .saved ? Color.brandSuccess : Color.brandDanger)
                            .frame(maxWidth: .infinity)
                            .transition(.opacity)
                    }

                    if let notes = camera.notes, !notes.isEmpty {
                        GlassCard(padding: AppSpacing.base) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("cameras_field_notes")
                                    .font(AppFont.label)
                                    .textCase(.uppercase)
                                    .foregroundStyle(.secondary)
                                Text(verbatim: notes)
                                    .font(AppFont.footnote)
                                    .foregroundStyle(.primary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.sm)
            }
        }
        .navigationTitle(Text(verbatim: camera.name))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Seed from the grid's cache so the page never opens blank, then
            // refresh every 2s while visible (`.task` cancels on disappear).
            image = service.latest[camera.id]?.image
            while !Task.isCancelled {
                if let fresh = await service.snapshot(for: camera) {
                    withAnimation(.smooth(duration: 0.25)) { image = fresh }
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private var snapshotArea: some View {
        Color.clear
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: fillsFrame ? .fill : .fit)
                } else {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("cameras_connecting")
                            .font(AppFont.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .background(Color.black.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                    .strokeBorder(Color.hairline, lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
            .onTapGesture {
                HapticFeedback.selection()
                withAnimation(.snappy(duration: 0.25)) { fillsFrame.toggle() }
            }
            .accessibilityLabel(Text(verbatim: camera.name))
            .accessibilityHint(Text("cameras_detail_hint"))
    }

    private func saveToPhotos() {
        guard let image else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                HapticFeedback.error()
                withAnimation(.smooth) { saveFeedback = .denied }
                return
            }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
                HapticFeedback.success()
                withAnimation(.smooth) { saveFeedback = .saved }
            } catch {
                HapticFeedback.error()
                debugLog("Snapshot save failed:", error)
            }
        }
    }
}

// MARK: - HomeKit camera detail (native live stream)

struct HomeKitCameraDetailView: View {
    let accessory: HMAccessory

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            VStack(spacing: AppSpacing.lg) {
                HomeKitCameraStreamView(accessory: accessory)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                            .strokeBorder(Color.hairline, lineWidth: 1)
                    )
                    .padding(.horizontal, AppSpacing.xl)
                    .accessibilityLabel(Text(verbatim: accessory.name))

                Text("cameras_homekit_live")
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(.top, AppSpacing.lg)
        }
        .navigationTitle(Text(verbatim: accessory.name))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Wraps HMCameraView around the accessory's HMCameraStreamControl —
/// stream starts when the view appears and stops when it's dismantled, so
/// no HomeKit session outlives the screen.
private struct HomeKitCameraStreamView: UIViewRepresentable {
    let accessory: HMAccessory

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> HMCameraView {
        let view = HMCameraView()
        context.coordinator.start(accessory: accessory, view: view)
        return view
    }

    func updateUIView(_ uiView: HMCameraView, context: Context) {}

    static func dismantleUIView(_ uiView: HMCameraView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator: NSObject, HMCameraStreamControlDelegate {
        private var control: HMCameraStreamControl?
        private weak var cameraView: HMCameraView?

        func start(accessory: HMAccessory, view: HMCameraView) {
            cameraView = view
            control = accessory.profiles
                .compactMap { $0 as? HMCameraProfile }
                .first?
                .streamControl
            control?.delegate = self
            control?.startStream()
        }

        func stop() {
            control?.stopStream()
            cameraView?.cameraSource = nil
        }

        func cameraStreamControlDidStartStream(_ cameraStreamControl: HMCameraStreamControl) {
            cameraView?.cameraSource = cameraStreamControl.cameraStream
        }

        func cameraStreamControl(_ cameraStreamControl: HMCameraStreamControl,
                                 didStopStreamWithError error: Error?) {
            if let error { debugLog("HomeKit stream stopped:", error) }
        }
    }
}
