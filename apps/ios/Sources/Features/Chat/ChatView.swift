import SwiftUI
import PhotosUI
import CoreLocation
import MapKit
import UserNotifications
import Supabase

private let kAvatarRingColorKey = "prvio.avatarRingColorName"

struct ChatView: View {
    @EnvironmentObject private var messageService: MessageService
    @EnvironmentObject private var familyService: FamilyService
    @EnvironmentObject private var propertyService: PropertyService
    @EnvironmentObject private var profileService: ProfileService
    @EnvironmentObject private var tabBarVis: TabBarVisibility
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var showAttachMenu = false
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var showLocationSheet = false
    @State private var showMentionPicker = false
    @State private var mentionedIds: [String] = []
    @State private var mentionedNames: [String] = []
    @State private var isSending = false
    @FocusState private var focused: Bool
    @AppStorage("prvio.avatarRingColorName") private var avatarRingColorName: String = "blue"

    private var propertyId: UUID? { propertyService.primary?.id }
    private var senderName: String {
        profileService.profile?.displayName
            ?? profileService.profile?.fullName
            ?? "Me"
    }
    private var ownerInitial: String {
        String((profileService.profile?.preferredName ?? senderName).prefix(1)).uppercased()
    }

    var body: some View {
        messageList
            .safeAreaInset(edge: .bottom, spacing: 0) {
                inputBar
            }
            .background(appBackground.ignoresSafeArea())
        .navigationTitle("Family Chat")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    HapticFeedback.selection()
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.75))
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                MemberAvatarStack(
                    members: familyService.members,
                    ownerAvatarUrl: profileService.profile?.avatarUrl,
                    ownerInitial: ownerInitial,
                    ringColor: avatarRingColor(for: avatarRingColorName)
                ) {
                    withAnimation { showMentionPicker.toggle() }
                }
            }
        }
        .task {
            guard let pid = propertyId else { return }
            await messageService.load(propertyId: pid)
            messageService.resetUnread()
            await messageService.loadReads(propertyId: pid)
            await messageService.markRead(propertyId: pid, readerName: senderName)
        }
        .task {
            guard let pid = propertyId else { return }
            await messageService.subscribeRealtime(propertyId: pid)
        }
        .task {
            guard let pid = propertyId else { return }
            await messageService.subscribeReads(propertyId: pid)
        }
        .onAppear { withAnimation(.easeInOut(duration: 0.2)) { tabBarVis.isHidden = true } }
        .onDisappear {
            withAnimation(.easeInOut(duration: 0.2)) { tabBarVis.isHidden = false }
            Task {
                await messageService.unsubscribe()
                await messageService.unsubscribeReads()
            }
        }
        .photosPicker(isPresented: $showAttachMenu,
                      selection: $photoPickerItems,
                      maxSelectionCount: 1,
                      matching: .images)
        .onChange(of: photoPickerItems) { _, items in
            Task { await sendPhoto(items) }
        }
        .sheet(isPresented: $showLocationSheet) {
            LocationShareSheet { lat, lon in
                Task { await sendLocation(lat: lat, lon: lon) }
            }
        }
        .sheet(isPresented: $showMentionPicker) {
            MentionPickerSheet(selectedIds: $mentionedIds, selectedNames: $mentionedNames)
        }
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 6) {
                    ForEach(messageService.messages) { msg in
                        MessageBubble(
                            message: msg,
                            isOwn: msg.senderId == supabase.auth.currentSession?.user.id,
                            members: familyService.members,
                            readers: messageService.reads[msg.id] ?? []
                        )
                        .id(msg.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messageService.messages.count) { _, _ in
                if let last = messageService.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
                // Mark newly-arrived messages as read while the chat is open.
                if let pid = propertyId {
                    Task { await messageService.markRead(propertyId: pid, readerName: senderName) }
                }
            }
            .onAppear {
                if let last = messageService.messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Input bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            if !mentionedNames.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(zip(mentionedIds, mentionedNames)), id: \.0) { id, name in
                            HStack(spacing: 4) {
                                Text("@\(name)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.blue)
                                Button {
                                    mentionedIds.removeAll { $0 == id }
                                    mentionedNames.removeAll { $0 == name }
                                } label: {
                                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.primary.opacity(0.5))
                                }
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.blue.opacity(0.15), in: Capsule())
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 6)
                }
            }

            HStack(spacing: 10) {
                Menu {
                    Button { showAttachMenu = true } label: { Label("Photo / Video", systemImage: "photo") }
                    Button { showLocationSheet = true } label: { Label("Share Location", systemImage: "location.fill") }
                    Button { focused = true; text = "@"; showMentionPicker = true } label: { Label("Mention Person", systemImage: "at") }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.blue)
                }

                TextField("Message…", text: $text, axis: .vertical)
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                    .tint(.blue)
                    .lineLimit(1...5)
                    .focused($focused)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))

                Button {
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    Task { await sendText() }
                } label: {
                    Image(systemName: isSending ? "clock" : "arrow.up.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(text.isEmpty ? Color.primary.opacity(0.25) : Color.blue)
                }
                .disabled(text.isEmpty || isSending)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Color.primary.opacity(0.04))
        }
    }

    // MARK: - Actions

    private func sendText() async {
        guard let pid = propertyId else { return }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = ""
        HapticFeedback.impact(.light)
        isSending = true
        defer { isSending = false }
        try? await messageService.send(
            propertyId: pid, senderName: senderName,
            body: body, mentionedIds: mentionedIds
        )
        // Local notification to mentioned members
        scheduleLocalMentionNotifications(body: body)
        mentionedIds = []; mentionedNames = []
    }

    private func sendPhoto(_ items: [PhotosPickerItem]) async {
        guard let pid = propertyId, let item = items.first else { return }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        isSending = true
        defer { isSending = false }
        let fileName = "\(UUID().uuidString).jpg"
        let filePath = "\(supabase.auth.currentSession?.user.id.uuidString ?? "anon")/chat/\(fileName)"
        try? await supabase.storage.from("documents")
            .upload(filePath, data: data, options: FileOptions(contentType: "image/jpeg", upsert: false))
        let url = try? supabase.storage.from("documents").getPublicURL(path: filePath)
        try? await messageService.send(
            propertyId: pid, senderName: senderName, body: nil,
            attachmentUrl: url?.absoluteString, attachmentType: "image",
            mentionedIds: mentionedIds
        )
        HapticFeedback.success()
        photoPickerItems = []
        mentionedIds = []; mentionedNames = []
    }

    private func sendLocation(lat: Double, lon: Double) async {
        guard let pid = propertyId else { return }
        isSending = true
        defer { isSending = false }
        try? await messageService.send(
            propertyId: pid, senderName: senderName,
            body: "📍 Shared a location",
            attachmentType: "location", latitude: lat, longitude: lon,
            mentionedIds: mentionedIds
        )
        HapticFeedback.success()
        mentionedIds = []; mentionedNames = []
    }

    private func scheduleLocalMentionNotifications(body: String) {
        guard !mentionedNames.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        for name in mentionedNames {
            let content = UNMutableNotificationContent()
            content.title = "\(senderName) mentioned \(name)"
            content.body = body
            content.sound = .default
            let req = UNNotificationRequest(
                identifier: "mention.\(UUID().uuidString)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            )
            center.add(req)
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: Message
    let isOwn: Bool
    let members: [FamilyMember]
    var readers: [MessageRead] = []

    @State private var showReaders = false

    private var sender: FamilyMember? {
        members.first { $0.name == message.senderName }
    }
    private var seen: Bool { !readers.isEmpty }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isOwn {
                Spacer(minLength: 60)
            } else {
                chatAvatar
            }

            VStack(alignment: isOwn ? .trailing : .leading, spacing: 3) {
                if !isOwn {
                    Text(message.senderName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(sender?.swiftColor ?? Color.primary.opacity(0.45))
                        .padding(.leading, 4)
                }
                bubbleContent
                statusRow
            }

            if !isOwn { Spacer(minLength: 60) }
        }
        .sheet(isPresented: $showReaders) {
            SeenBySheet(readers: readers, members: members)
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        if isOwn {
            Button {
                if seen { showReaders = true }
            } label: {
                HStack(spacing: 4) {
                    Text(message.timeDisplay)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.primary.opacity(0.3))
                    ReadCheck(seen: seen)
                }
                .padding(.horizontal, 4)
            }
            .buttonStyle(.plain)
            .disabled(!seen)
        } else {
            Text(message.timeDisplay)
                .font(.system(size: 10))
                .foregroundStyle(Color.primary.opacity(0.3))
                .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private var chatAvatar: some View {
        if let member = sender {
            ZStack {
                Circle()
                    .fill(member.swiftColor.opacity(0.18))
                Text(member.initials)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(member.swiftColor)
            }
            .frame(width: 32, height: 32)
            .overlay(
                Circle()
                    .strokeBorder(member.swiftColor, lineWidth: 2)
            )
        } else {
            Circle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 32, height: 32)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1.5))
        }
    }

    @ViewBuilder
    private var bubbleContent: some View {
        if message.isLocationMessage, let lat = message.latitude, let lon = message.longitude {
            LocationBubble(lat: lat, lon: lon, isOwn: isOwn)
        } else if message.isImageMessage, let urlStr = message.attachmentUrl, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                if case .success(let img) = phase {
                    img.resizable().scaledToFill()
                        .frame(maxWidth: 220, maxHeight: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                } else {
                    RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.07))
                        .frame(width: 160, height: 120)
                        .overlay(ProgressView().tint(.white))
                }
            }
        } else {
            Text(message.body ?? "")
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(isOwn ? Color.blue.opacity(0.75) : Color.primary.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

// MARK: - Read Receipt Check

private struct ReadCheck: View {
    let seen: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
                .offset(x: 3.5)
        }
        .frame(width: 14, alignment: .leading)
        .foregroundStyle(seen ? Color.blue : Color.primary.opacity(0.4))
    }
}

// MARK: - Seen By sheet

private struct SeenBySheet: View {
    let readers: [MessageRead]
    let members: [FamilyMember]
    @Environment(\.dismiss) private var dismiss

    private func member(for name: String) -> FamilyMember? {
        members.first { $0.name == name }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(readers.sorted { $0.readAt > $1.readAt }) { read in
                            HStack(spacing: 12) {
                                avatar(for: read)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(read.readerName.isEmpty ? "Member" : read.readerName)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(.primary)
                                    Text("Seen \(read.readTimeDisplay)")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.primary.opacity(0.45))
                                }
                                Spacer()
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.blue)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 8)
                }
            }
            .navigationTitle("Seen by \(readers.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.font(.system(size: 15, weight: .semibold)).foregroundStyle(.blue)
                }
            }
        }
    }

    @ViewBuilder
    private func avatar(for read: MessageRead) -> some View {
        let m = member(for: read.readerName)
        let color = m?.swiftColor ?? .blue
        ZStack {
            Circle().fill(color.opacity(0.2))
            Text(m?.initials ?? String(read.readerName.prefix(1)).uppercased())
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(color)
        }
        .frame(width: 38, height: 38)
        .overlay(Circle().strokeBorder(color, lineWidth: 1.5))
    }
}

// MARK: - Location Bubble

private struct LocationBubble: View {
    let lat: Double
    let lon: Double
    let isOwn: Bool

    @State private var region: MKCoordinateRegion

    init(lat: Double, lon: Double, isOwn: Bool) {
        self.lat = lat; self.lon = lon; self.isOwn = isOwn
        _region = State(initialValue: MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        ))
    }

    var body: some View {
        Map(coordinateRegion: $region, annotationItems: [MapPin(lat: lat, lon: lon)]) { pin in
            MapMarker(coordinate: pin.coordinate, tint: .blue)
        }
        .frame(width: 220, height: 140)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture {
            let q = "\(lat),\(lon)"
            if let url = URL(string: "maps://?q=\(q)&ll=\(q)") { UIApplication.shared.open(url) }
        }
    }
}

private struct MapPin: Identifiable {
    let id = UUID()
    let lat: Double
    let lon: Double
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
}

// MARK: - Location share sheet

struct LocationShareSheet: View {
    let onShare: (Double, Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var locMgr = LocationManager()

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                VStack(spacing: 24) {
                    if let loc = locMgr.location {
                        Map(coordinateRegion: .constant(MKCoordinateRegion(
                            center: loc.coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                        )), annotationItems: [MapPin(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude)]) { pin in
                            MapMarker(coordinate: pin.coordinate, tint: .blue)
                        }
                        .frame(maxWidth: .infinity).frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 20)

                        Button {
                            onShare(loc.coordinate.latitude, loc.coordinate.longitude)
                            dismiss()
                        } label: {
                            Label("Share This Location", systemImage: "location.fill")
                                .font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                                .frame(maxWidth: .infinity).padding(.vertical, 15)
                                .background(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing),
                                            in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                    } else {
                        Spacer()
                        ProgressView().tint(.white)
                        Text(locMgr.denied ? "Location access denied. Enable in Settings." : "Getting your location…")
                            .font(.system(size: 14)).foregroundStyle(Color.primary.opacity(0.5))
                        Spacer()
                    }
                }
                .padding(.top, 16)
            }
            .navigationTitle("Share Location").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.foregroundStyle(Color.primary.opacity(0.7)) }
            }
        }
        .task { locMgr.requestLocation() }
    }
}

// MARK: - Mention picker sheet

private struct MentionPickerSheet: View {
    @EnvironmentObject private var familyService: FamilyService
    @Binding var selectedIds: [String]
    @Binding var selectedNames: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 0) {
                        MemberPickerView(selectedIds: $selectedIds, selectedNames: $selectedNames)
                            .padding(.horizontal, 20).padding(.top, 8)
                    }
                }
            }
            .navigationTitle("Mention").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.font(.system(size: 15, weight: .semibold)).foregroundStyle(.blue)
                }
            }
        }
    }
}

// MARK: - Location Manager

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var location: CLLocation?
    @Published var denied = false
    private let mgr = CLLocationManager()

    override init() {
        super.init()
        mgr.delegate = self
        mgr.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestLocation() {
        let status = mgr.authorizationStatus
        if status == .notDetermined { mgr.requestWhenInUseAuthorization() }
        else if status == .denied { denied = true }
        else { mgr.requestLocation() }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .denied { denied = true }
        else if manager.authorizationStatus != .notDetermined { mgr.requestLocation() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
