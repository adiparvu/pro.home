import SwiftUI
import Vision
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Receipt Scanner (OCR)

struct ReceiptScannerView: View {
    @EnvironmentObject private var receiptService: ReceiptService
    @EnvironmentObject private var propertyService: PropertyService
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var sourceImage: UIImage? = nil
    @State private var isProcessing = false
    @State private var parsed: ParsedReceipt? = nil
    @State private var showCamera = false
    @State private var showFileImporter = false

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()

                if let parsed {
                    ReceiptReviewView(parsed: parsed, onSave: { p in
                        Task { await saveReceipt(p) }
                    })
                    .environmentObject(receiptService)
                    .environmentObject(propertyService)
                } else {
                    pickPhotoState
                }
            }
            .navigationTitle(String(localized: "scanner_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                if parsed != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(String(localized: "scanner_rescan")) {
                            withAnimation { self.parsed = nil; sourceImage = nil }
                        }
                    }
                }
            }
            .onChange(of: selectedPhotoItem) { _, item in
                Task { await loadAndProcess(item) }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraCapture { image in
                    showCamera = false
                    isProcessing = true
                    Task {
                        isProcessing = true
                        defer { isProcessing = false }
                        let parsed = await performOCR(on: image)
                        withAnimation { self.parsed = parsed }
                    }
                }
                .ignoresSafeArea()
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.image, .jpeg, .png, .heic, .pdf],
                allowsMultipleSelection: false
            ) { result in
                if let url = try? result.get().first,
                   url.startAccessingSecurityScopedResource(),
                   let data = try? Data(contentsOf: url),
                   let image = UIImage(data: data) {
                    url.stopAccessingSecurityScopedResource()
                    isProcessing = true
                    Task {
                        defer { isProcessing = false }
                        let parsed = await performOCR(on: image)
                        withAnimation { self.parsed = parsed }
                    }
                }
            }
        }
    }

    // MARK: - Pick photo state

    private var pickPhotoState: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 100, height: 100)
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(Color.accentColor)
                }

                Text(String(localized: "scanner_headline"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)

                Text(String(localized: "scanner_body"))
                    .font(.system(size: 14))
                    .foregroundStyle(Color.primary.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            if isProcessing {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(Color.accentColor)
                    Text(String(localized: "scanner_processing"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 12) {
                    Button {
                        showCamera = true
                    } label: {
                        Label(String(localized: "Fotografiază bon"), systemImage: "camera.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 12) {
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            Label(String(localized: "scanner_choose_photo"), systemImage: "photo.on.rectangle")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                                .frame(maxWidth: .infinity)
                                .frame(height: 46)
                                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            showFileImporter = true
                        } label: {
                            Label(String(localized: "Din fișiere"), systemImage: "doc.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.primary.opacity(0.7))
                                .frame(maxWidth: .infinity)
                                .frame(height: 46)
                                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    Text(String(localized: "scanner_tip"))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.primary.opacity(0.4))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                .padding(.horizontal, 20)
            }

            Spacer()
        }
    }

    // MARK: - Load and OCR

    private func loadAndProcess(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        isProcessing = true
        defer { isProcessing = false }

        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        sourceImage = image

        let parsed = await performOCR(on: image)
        withAnimation(.easeInOut(duration: 0.3)) { self.parsed = parsed }
    }

    private func performOCR(on image: UIImage) async -> ParsedReceipt {
        await withCheckedContinuation { continuation in
            guard let cgImage = image.cgImage else {
                continuation.resume(returning: ParsedReceipt())
                return
            }

            let request = VNRecognizeTextRequest { req, _ in
                let observations = (req.results as? [VNRecognizedTextObservation]) ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                let result = ReceiptParser.parse(lines: lines)
                continuation.resume(returning: result)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }

    // MARK: - Save

    private func saveReceipt(_ parsed: ParsedReceipt) async {
        guard let propId = propertyService.primary?.id else { return }
        let now = ISO8601DateFormatter().string(from: Date())
        let payload = NewReceiptPayload(
            propertyId: propId,
            storeName: parsed.storeName,
            date: parsed.dateString,
            total: parsed.total,
            category: parsed.category,
            imageUrl: nil,
            notes: parsed.notes,
            createdAt: now,
            updatedAt: now
        )
        let items = parsed.items.map { item in
            NewReceiptItemPayload(
                receiptId: UUID(),
                propertyId: propId,
                name: item.name,
                quantity: item.quantity,
                unitPrice: item.unitPrice,
                totalPrice: item.totalPrice,
                category: parsed.category,
                createdAt: now
            )
        }
        do {
            try await receiptService.addReceipt(payload, items: items)
            HapticFeedback.success()
            dismiss()
        } catch {
            HapticFeedback.error()
        }
    }
}

// MARK: - Receipt Review

private struct ReceiptReviewView: View {
    @EnvironmentObject private var receiptService: ReceiptService
    @EnvironmentObject private var propertyService: PropertyService
    @Environment(\.dismiss) private var dismiss

    @State var parsed: ParsedReceipt
    var onSave: (ParsedReceipt) -> Void

    @State private var isSaving = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                // Store + date
                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("STORE")
                    TextField(String(localized: "scanner_store_placeholder"), text: $parsed.storeName)
                        .font(.system(size: 16))
                        .padding(14)
                        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("DATE")
                    DatePicker("", selection: Binding(
                        get: { parsed.dateValue },
                        set: { parsed.dateString = ReceiptParser.isoDate($0) }
                    ), displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .padding(.vertical, 4)
                }

                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("CATEGORY")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(ReceiptCategory.all, id: \.id) { cat in
                                Button { parsed.category = cat.id; HapticFeedback.selection() } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: ReceiptCategory.icon(for: cat.id)).font(.system(size: 11))
                                        Text(cat.label).font(.system(size: 13))
                                    }
                                    .foregroundStyle(parsed.category == cat.id ? .white : Color.primary.opacity(0.7))
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(parsed.category == cat.id
                                        ? ReceiptCategory.color(for: cat.id) : Color.primary.opacity(0.07),
                                                in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // Items
                if !parsed.items.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel("ITEMS (\(parsed.items.count))")
                        GlassCard(padding: 0) {
                            VStack(spacing: 0) {
                                ForEach(Array(parsed.items.enumerated()), id: \.offset) { idx, item in
                                    HStack {
                                        Text(item.name).font(.system(size: 13)).foregroundStyle(.primary).lineLimit(1)
                                        Spacer()
                                        Text(Receipt.format(item.totalPrice))
                                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary).monospacedDigit()
                                    }
                                    .padding(.horizontal, 14).padding(.vertical, 9)
                                    if idx < parsed.items.count - 1 {
                                        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 14)
                                    }
                                }
                            }
                        }
                    }
                }

                // Total
                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("TOTAL")
                    HStack {
                        TextField("0.00", value: $parsed.total, format: .number.precision(.fractionLength(2)))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .keyboardType(.decimalPad)
                    }
                    .padding(14)
                    .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Button {
                    isSaving = true
                    onSave(parsed)
                } label: {
                    Group {
                        if isSaving { ProgressView().tint(Color(UIColor.systemBackground)) }
                        else {
                            Label(String(localized: "scanner_save"), systemImage: "checkmark")
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                    .foregroundStyle(Color(UIColor.systemBackground))
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isSaving)

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20).padding(.top, 16)
        }
    }

    private func fieldLabel(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
    }
}

// MARK: - Parsed Receipt

struct ParsedReceipt {
    var storeName: String = ""
    var dateString: String = ReceiptParser.isoDate(Date())
    var total: Double = 0
    var category: String = "food"
    var items: [ParsedItem] = []
    var notes: String? = nil

    var dateValue: Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: dateString) ?? Date()
    }
}

struct ParsedItem {
    var name: String
    var quantity: Double
    var unitPrice: Double
    var totalPrice: Double
}

// MARK: - Receipt Parser (OCR → structured data)

enum ReceiptParser {
    static func isoDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    static func parse(lines: [String]) -> ParsedReceipt {
        var result = ParsedReceipt()
        guard !lines.isEmpty else { return result }

        // 1. Store name — first non-empty, non-date, non-price-only line
        result.storeName = extractStoreName(from: lines)

        // 2. Date
        if let dateStr = extractDate(from: lines) {
            result.dateString = dateStr
        }

        // 3. Items + total
        let (items, total) = extractItemsAndTotal(from: lines)
        result.items = items
        result.total = total > 0 ? total : items.reduce(0) { $0 + $1.totalPrice }

        // 4. Category heuristic from store name + items
        result.category = guessCategory(storeName: result.storeName, items: items)

        return result
    }

    private static func extractStoreName(from lines: [String]) -> String {
        let datePattern = #/\d{1,2}[./-]\d{1,2}[./-]\d{2,4}/#
        let pricePattern = #/^\d+[.,]\d{2}\s*$/#
        for line in lines.prefix(5) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.count > 2 else { continue }
            guard (try? datePattern.firstMatch(in: trimmed)) == nil else { continue }
            guard (try? pricePattern.firstMatch(in: trimmed)) == nil else { continue }
            return trimmed
        }
        return ""
    }

    private static func extractDate(from lines: [String]) -> String? {
        let patterns: [String] = [
            #"\b(\d{4})[./-](\d{1,2})[./-](\d{1,2})\b"#,
            #"\b(\d{1,2})[./-](\d{1,2})[./-](\d{4})\b"#,
            #"\b(\d{1,2})[./-](\d{1,2})[./-](\d{2})\b"#,
        ]
        for line in lines {
            for pattern in patterns {
                if let match = line.range(of: pattern, options: .regularExpression) {
                    let dateStr = String(line[match])
                        .trimmingCharacters(in: .whitespaces)
                        .replacingOccurrences(of: "/", with: "-")
                        .replacingOccurrences(of: ".", with: "-")

                    let parts = dateStr.components(separatedBy: "-").map { Int($0) ?? 0 }
                    guard parts.count == 3 else { continue }
                    if parts[0] > 1900 {
                        // yyyy-mm-dd
                        return String(format: "%04d-%02d-%02d", parts[0], parts[1], parts[2])
                    } else if parts[2] > 1900 {
                        // dd-mm-yyyy
                        return String(format: "%04d-%02d-%02d", parts[2], parts[1], parts[0])
                    } else if parts[2] > 0 {
                        // dd-mm-yy
                        let year = parts[2] < 50 ? 2000 + parts[2] : 1900 + parts[2]
                        return String(format: "%04d-%02d-%02d", year, parts[1], parts[0])
                    }
                }
            }
        }
        return nil
    }

    private static func extractItemsAndTotal(from lines: [String]) -> ([ParsedItem], Double) {
        // Price pattern: number ending with decimal separator + 2 digits
        let priceRegex = #/(\d{1,6}[.,]\d{2})\s*$/#
        let totalKeywords = ["total", "totaal", "totale", "gesamt", "summa", "suma", "lei", "grand", "amount"]
        var items: [ParsedItem] = []
        var total: Double = 0

        for line in lines {
            let lower = line.lowercased()
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.count > 2 else { continue }

            guard let match = try? priceRegex.firstMatch(in: trimmed) else { continue }
            let priceStr = String(match.1).replacingOccurrences(of: ",", with: ".")
            guard let price = Double(priceStr), price > 0 else { continue }

            let isTotal = totalKeywords.contains(where: { lower.contains($0) })
            if isTotal {
                if price > total { total = price }
                continue
            }

            // Extract name (everything before the price)
            let nameRange = trimmed.range(of: String(match.1))
            let name = nameRange != nil
                ? trimmed[..<nameRange!.lowerBound].trimmingCharacters(in: .whitespaces)
                : trimmed

            guard name.count > 1 && !name.allSatisfy({ $0.isNumber || $0 == "." || $0 == "," || $0 == " " }) else { continue }

            items.append(ParsedItem(name: name.capitalized, quantity: 1, unitPrice: price, totalPrice: price))
        }

        return (items, total)
    }

    private static func guessCategory(storeName: String, items: [ParsedItem]) -> String {
        let lower = storeName.lowercased()
        let foodKeywords = ["kaufland", "lidl", "aldi", "mega", "carrefour", "penny", "market", "supermarket",
                            "magazin", "shop", "food", "alimentar", "piata", "piaţa", "consum", "profi"]
        let pharmacyKeywords = ["pharmacy", "farma", "farmacia", "apotek", "apotheke", "dr max", "helpnet"]
        let hardwareKeywords = ["dedeman", "brico", "leroy", "hornbach", "bauhaus", "hardware", "bricolaj"]
        let clothingKeywords = ["zara", "h&m", "hm ", "fashion", "clothing", "moda", "new yorker"]
        let diningKeywords = ["restaurant", "pizzeria", "cafe", "cafenea", "mcdonalds", "kfc", "burger"]

        if foodKeywords.contains(where: { lower.contains($0) }) { return "food" }
        if pharmacyKeywords.contains(where: { lower.contains($0) }) { return "health" }
        if hardwareKeywords.contains(where: { lower.contains($0) }) { return "diy" }
        if clothingKeywords.contains(where: { lower.contains($0) }) { return "clothing" }
        if diningKeywords.contains(where: { lower.contains($0) }) { return "dining" }
        return "other"
    }
}
