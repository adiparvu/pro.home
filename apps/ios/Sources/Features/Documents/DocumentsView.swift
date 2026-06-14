import SwiftUI
import UniformTypeIdentifiers
import QuickLook

struct DocumentsView: View {
    @EnvironmentObject private var documentService: DocumentService
    @EnvironmentObject private var propertyService: PropertyService
    @State private var search = ""
    @State private var selectedCategory: String? = nil
    @State private var showAdd = false
    @State private var docToDelete: DocumentModel?
    @State private var showDeleteConfirm = false
    @State private var previewURL: URL?
    @State private var errorToast: String?

    private let categories = ["All", "warranty", "contract", "insurance",
                               "certificate", "manual", "invoice", "photo", "other"]

    var filteredDocuments: [DocumentModel] {
        var docs = documentService.documents
        if let cat = selectedCategory, cat != "All" {
            docs = docs.filter { $0.category == cat }
        }
        if !search.isEmpty {
            docs = docs.filter {
                $0.name.localizedCaseInsensitiveContains(search) ||
                $0.category.localizedCaseInsensitiveContains(search)
            }
        }
        return docs
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                PageHeader(title: "Documents",
                           trailing: AnyView(
                            HStack(spacing: 10) {
                                filterMenu
                                Button {
                                    if propertyService.primary == nil {
                                        errorToast = "Please set up your property first in Settings."
                                    } else {
                                        showAdd = true
                                    }
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 22))
                                        .foregroundStyle(.primary)
                                }
                            }
                           ))
                    .padding(.bottom, 12)

                searchBar
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                if documentService.isLoading {
                    Spacer()
                    ProgressView().tint(.white)
                    Spacer()
                } else if filteredDocuments.isEmpty {
                    emptyState
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 12) {
                            if !documentService.expiringDocs.isEmpty && selectedCategory == nil && search.isEmpty {
                                expiringBanner
                            }
                            ForEach(filteredDocuments) { doc in
                                DocumentRow(doc: doc) {
                                    openDocument(doc)
                                } onDelete: {
                                    docToDelete = doc
                                    showDeleteConfirm = true
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                        .padding(.top, 4)
                        .padding(.bottom, 120)
                    }
                    .refreshable { await documentService.load() }
                }
            }
        }
        .task { await documentService.load() }
        .sheet(isPresented: $showAdd) {
            if let propertyId = propertyService.primary?.id {
                AddDocumentSheet(propertyId: propertyId) { await documentService.load() }
                    .environmentObject(documentService)
            }
        }
        .confirmationDialog("Delete \"\(docToDelete?.name ?? "document")\"?",
                            isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let doc = docToDelete {
                    Task { await documentService.delete(doc) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove the file and cannot be undone.")
        }
        .quickLookPreview($previewURL)
        .onChange(of: documentService.error) { _, err in
            if let err { errorToast = err }
        }
        .overlay(alignment: .bottom) {
            if let msg = errorToast {
                toastView(msg)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 110)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                            withAnimation { errorToast = nil }
                        }
                    }
            }
        }
    }

    private func openDocument(_ doc: DocumentModel) {
        guard let url = URL(string: doc.fileUrl) else { return }
        // Try QuickLook for local-accessible URLs, else open in browser
        if doc.mimeType == "application/pdf" || doc.mimeType?.hasPrefix("image/") == true {
            // Download and preview
            Task {
                if let data = try? Data(contentsOf: url) {
                    let tmp = FileManager.default.temporaryDirectory
                        .appendingPathComponent(doc.fileName)
                    try? data.write(to: tmp)
                    await MainActor.run { previewURL = tmp }
                } else {
                    await UIApplication.shared.open(url)
                }
            }
        } else {
            UIApplication.shared.open(url)
        }
    }

    private func toastView(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(.red.opacity(0.85), in: Capsule())
            .padding(.horizontal, 24)
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(Color.primary.opacity(0.4))
            TextField("Search documents...", text: $search)
                .font(.system(size: 15)).foregroundStyle(.primary).tint(.blue)
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.primary.opacity(0.4))
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Category filter menu

    private var filterMenu: some View {
        Menu {
            Button {
                withAnimation(.spring(response: 0.25)) { selectedCategory = nil }
            } label: {
                Label("All  (\(documentService.documents.count))",
                      systemImage: selectedCategory == nil ? "checkmark" : "square.grid.2x2.fill")
            }
            ForEach(categories.dropFirst(), id: \.self) { cat in
                Button {
                    withAnimation(.spring(response: 0.25)) { selectedCategory = cat }
                } label: {
                    Label("\(cat.capitalized)  (\(countFor(cat)))",
                          systemImage: selectedCategory == cat ? "checkmark" : categoryIcon(for: cat))
                }
            }
        } label: {
            HStack(spacing: 5) {
                if let cat = selectedCategory {
                    Image(systemName: categoryIcon(for: cat))
                        .font(.system(size: 12, weight: .semibold))
                    Text(cat.capitalized)
                        .font(.system(size: 13, weight: .semibold))
                } else {
                    Text("…")
                        .font(.system(size: 15, weight: .semibold))
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        }
    }

    private func categoryIcon(for cat: String) -> String {
        switch cat {
        case "warranty":    return "checkmark.seal.fill"
        case "contract":    return "doc.text.fill"
        case "insurance":   return "shield.fill"
        case "certificate": return "star.seal.fill"
        case "manual":      return "book.fill"
        case "invoice":     return "banknote.fill"
        case "photo":       return "photo.fill"
        default:            return "folder.fill"
        }
    }

    private func countFor(_ cat: String) -> Int {
        documentService.documents.filter { $0.category == cat }.count
    }

    // MARK: - Expiring banner

    private var expiringBanner: some View {
        GlassCard {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).font(.system(size: 18))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(documentService.expiringDocs.count) document\(documentService.expiringDocs.count == 1 ? "" : "s") expiring soon")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.primary)
                    Text("Review and renew before they expire")
                        .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.5))
                }
                Spacer()
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 52)).foregroundStyle(Color.primary.opacity(0.15))
            VStack(spacing: 8) {
                Text(search.isEmpty ? "No documents yet" : "No results found")
                    .font(.system(size: 18, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.6))
                if search.isEmpty {
                    Text("Tap + to add your first document")
                        .font(.system(size: 14)).foregroundStyle(Color.primary.opacity(0.35))
                }
            }
            Spacer()
        }
    }
}

// MARK: - Document Row

struct DocumentRow: View {
    let doc: DocumentModel
    let onOpen: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onOpen) {
            GlassCard {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primary.opacity(0.08)).frame(width: 48, height: 48)
                        Image(systemName: doc.categoryIcon)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(categoryColor)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(doc.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary).lineLimit(1)
                            if doc.isCritical {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.system(size: 12)).foregroundStyle(.red)
                            }
                        }
                        HStack(spacing: 8) {
                            Text(doc.category.capitalized)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(categoryColor.opacity(0.8))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(categoryColor.opacity(0.12), in: Capsule())
                            if !doc.fileSizeDisplay.isEmpty {
                                Text(doc.fileSizeDisplay)
                                    .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.35))
                            }
                        }
                        if let expiry = doc.expiresDisplay {
                            HStack(spacing: 4) {
                                Image(systemName: "calendar").font(.system(size: 10))
                                Text("Expires \(expiry)").font(.system(size: 11))
                            }
                            .foregroundStyle(doc.isExpiringSoon ? .orange : Color.primary.opacity(0.4))
                        }
                    }

                    Spacer()

                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 18)).foregroundStyle(.blue.opacity(0.7))
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var categoryColor: Color {
        switch doc.category {
        case "warranty":    return .yellow
        case "contract":    return .blue
        case "insurance":   return Color(red: 0.3, green: 0.85, blue: 0.5)
        case "certificate": return .purple
        case "manual":      return .cyan
        case "invoice":     return .orange
        case "photo":       return .pink
        default:            return .white
        }
    }
}

// MARK: - Add Document Sheet

struct AddDocumentSheet: View {
    let propertyId: UUID
    let onSaved: () async -> Void

    @EnvironmentObject private var documentService: DocumentService
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var category = "contract"
    @State private var expiryDate: Date = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var hasExpiry = false
    @State private var isCritical = false
    @State private var showFilePicker = false
    @State private var pickedFileData: Data?
    @State private var pickedFileName = ""
    @State private var pickedMimeType = "application/octet-stream"
    @State private var error: String?
    @State private var isSaving = false

    private let categories = ["contract", "warranty", "insurance", "certificate",
                               "manual", "invoice", "photo", "other"]

    var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && pickedFileData != nil }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        // Name
                        fieldGroup {
                            rowField("doc.text.fill", "Document name") {
                                TextField("e.g. Home Insurance 2025", text: $name)
                                    .font(.system(size: 15)).foregroundStyle(.primary).tint(.blue)
                                    .autocorrectionDisabled()
                            }
                        }

                        // Category
                        fieldGroup {
                            HStack(spacing: 12) {
                                iconLabel("tag.fill", color: .purple, text: "Category")
                                Spacer()
                                Picker("", selection: $category) {
                                    ForEach(categories, id: \.self) { c in
                                        Text(c.capitalized).tag(c)
                                    }
                                }
                                .tint(Color.primary.opacity(0.7))
                            }
                            .padding(.horizontal, 16).padding(.vertical, 13)
                        }

                        // Expiry
                        fieldGroup {
                            VStack(spacing: 0) {
                                HStack(spacing: 12) {
                                    iconLabel("calendar", color: .orange, text: "Has expiry date")
                                    Spacer()
                                    Toggle("", isOn: $hasExpiry).labelsHidden().tint(.blue)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 13)

                                if hasExpiry {
                                    div
                                    DatePicker("", selection: $expiryDate, in: Date()..., displayedComponents: .date)
                                        .datePickerStyle(.compact)
                                        .colorScheme(.dark)
                                        .padding(.horizontal, 16).padding(.vertical, 10)
                                }
                            }
                        }

                        // Critical
                        fieldGroup {
                            HStack(spacing: 12) {
                                iconLabel("exclamationmark.circle.fill", color: .red, text: "Critical document")
                                Spacer()
                                Toggle("", isOn: $isCritical).labelsHidden().tint(.red)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 13)
                        }

                        // File picker
                        fieldGroup {
                            Button { showFilePicker = true } label: {
                                HStack(spacing: 12) {
                                    iconLabel("paperclip", color: .blue, text: pickedFileName.isEmpty ? "Attach file" : pickedFileName)
                                    Spacer()
                                    Image(systemName: pickedFileData != nil ? "checkmark.circle.fill" : "chevron.right")
                                        .font(.system(size: 14))
                                        .foregroundStyle(pickedFileData != nil ? Color(red: 0.3, green: 0.85, blue: 0.5) : Color.primary.opacity(0.3))
                                }
                                .padding(.horizontal, 16).padding(.vertical, 13)
                            }
                            .buttonStyle(.plain)
                        }

                        if let err = error {
                            Text(err).font(.system(size: 13)).foregroundStyle(.red)
                                .multilineTextAlignment(.center).padding(.horizontal, 8)
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20).padding(.top, 20)
                }
            }
            .navigationTitle("Add Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.primary.opacity(0.7))
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().tint(.blue)
                    } else {
                        Button("Save") { Task { await save() } }
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(.blue)
                            .disabled(!canSave)
                    }
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.pdf, .jpeg, .png, .webP, .heic, .plainText, .data],
                allowsMultipleSelection: false
            ) { result in
                handleFilePick(result)
            }
        }
    }

    private func handleFilePick(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let data = try? Data(contentsOf: url) else {
                error = "Could not read the selected file."
                return
            }
            pickedFileData = data
            pickedFileName = url.lastPathComponent
            if name.isEmpty { name = url.deletingPathExtension().lastPathComponent }
            let ext = url.pathExtension.lowercased()
            pickedMimeType = UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
        case .failure(let err):
            error = err.localizedDescription
        }
    }

    private func save() async {
        guard let fileData = pickedFileData else { return }
        isSaving = true
        error = nil
        do {
            let expiryStr: String? = hasExpiry ? ISO8601DateFormatter.yearMonthDay.string(from: expiryDate) : nil
            try await documentService.add(
                propertyId: propertyId,
                name: name.trimmingCharacters(in: .whitespaces),
                category: category,
                fileData: fileData,
                fileName: pickedFileName,
                mimeType: pickedMimeType,
                expiresAt: expiryStr,
                isCritical: isCritical
            )
            HapticFeedback.success()
            dismiss()
            await onSaved()
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }

    private func fieldGroup<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
    }

    private func rowField<Content: View>(_ icon: String, _ placeholder: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            iconLabel(icon, color: .blue, text: "")
            content()
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    private func iconLabel(_ icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(color).frame(width: 22)
            if !text.isEmpty {
                Text(text).font(.system(size: 15)).foregroundStyle(.primary).lineLimit(1)
            }
        }
    }

    private var div: some View {
        Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 0.5).padding(.leading, 52)
    }
}

extension ISO8601DateFormatter {
    static let yearMonthDay: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        return f
    }()
}
