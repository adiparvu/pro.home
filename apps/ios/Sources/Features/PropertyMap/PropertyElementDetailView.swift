import SwiftUI
import PhotosUI
import Supabase

struct PropertyElementDetailView: View {
    let element: PropertyElement

    @EnvironmentObject private var elementService: PropertyElementService
    @EnvironmentObject private var currencyService: CurrencyService
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var documentService: DocumentService
    @EnvironmentObject private var taskService: TaskService
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: DetailTab = .info
    @State private var showAddRecord = false
    @State private var showEditElement = false
    @State private var localElement: PropertyElement
    @State private var showDeleteConfirm = false
    @State private var showLocationPicker = false
    @State private var showLinkDocument = false
    @State private var showLinkTask = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var isUploading = false

    init(element: PropertyElement) {
        self.element = element
        _localElement = State(initialValue: element)
    }

    enum DetailTab: String, CaseIterable {
        case info      = "Info"
        case records   = "History"
        case documents = "Documents"
        case tasks     = "Tasks"

        var icon: String {
            switch self {
            case .info:      return "info.circle"
            case .records:   return "clock.arrow.circlepath"
            case .documents: return "doc.fill"
            case .tasks:     return "checklist"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    elementHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 12)

                    healthSection
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)

                    DetailTabBar(selected: $selectedTab)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            switch selectedTab {
                            case .info:      infoTab
                            case .records:   recordsTab
                            case .documents: documentsTab
                            case .tasks:     tasksTab
                            }
                            Spacer(minLength: 60)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 22))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showEditElement = true } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            Label("Delete element", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 20))
                    }
                }
            }
        }
        .sheet(isPresented: $showAddRecord) {
            AddElementRecordView(element: localElement) { payload in
                Task { await elementService.addRecord(payload) }
            }
        }
        .sheet(isPresented: $showEditElement) {
            EditPropertyElementView(element: $localElement) {
                Task { await elementService.update(localElement) }
            }
        }
        .sheet(isPresented: $showLocationPicker) {
            ObjectLocationPicker(element: localElement)
        }
        .sheet(isPresented: $showLinkDocument) {
            DocumentLinkPicker(elementId: localElement.id)
                .environmentObject(documentService)
        }
        .sheet(isPresented: $showLinkTask) {
            TaskLinkPicker(elementId: localElement.id)
                .environmentObject(taskService)
        }
        .onChange(of: photoItems) { _, items in
            Task { await uploadPhotos(items) }
        }
        .confirmationDialog("Delete \(localElement.name)?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    await elementService.delete(localElement)
                    dismiss()
                }
            }
        }
        .task {
            await elementService.loadRecords(elementId: localElement.id)
        }
        .onReceive(elementService.$elements) { updated in
            if let fresh = updated.first(where: { $0.id == localElement.id }) {
                localElement = fresh
            }
        }
    }

    // MARK: - Header

    private var elementHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(localElement.elementType.accentColor.opacity(0.2))
                    .frame(width: 60, height: 60)
                Image(systemName: localElement.elementType.icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(localElement.elementType.accentColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(localElement.name)
                    .font(.title3.weight(.bold))
                HStack(spacing: 8) {
                    Text(localElement.elementType.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("•")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                    conditionBadge
                }
                if let brand = localElement.brand, let model = localElement.model {
                    Text("\(brand) \(model)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else if let brand = localElement.brand {
                    Text(brand)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            warrantyBadge
        }
    }

    private var conditionBadge: some View {
        Text(localElement.technicalCondition.displayName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(localElement.technicalCondition.color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(localElement.technicalCondition.color.opacity(0.15)))
    }

    private var warrantyBadge: some View {
        let status = localElement.warrantyStatus
        return VStack(spacing: 2) {
            Image(systemName: status == .none ? "shield.slash" : "shield.fill")
                .font(.system(size: 16))
                .foregroundStyle(status.color)
            Text(status.label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(status.color)
                .multilineTextAlignment(.center)
        }
        .frame(width: 60)
    }

    // MARK: - Health

    private var healthSection: some View {
        GlassCard(padding: 14) {
            VStack(spacing: 8) {
                HStack {
                    Text("Technical condition")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(localElement.healthScore)/100")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(localElement.healthColor)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08)).frame(height: 8)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [localElement.healthColor.opacity(0.7), localElement.healthColor],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * CGFloat(localElement.healthScore) / 100, height: 8)
                    }
                }
                .frame(height: 8)
            }
        }
    }
}
