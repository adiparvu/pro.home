import SwiftUI
import Charts
import Vision
import PhotosUI

struct UtilityEntry: Identifiable, Codable {
    var id = UUID()
    var type: String      // "electricity" | "water" | "gas" | "internet" | "other"
    var amount: Double
    var month: String     // "yyyy-MM"
    var unit: String      // "kWh", "m³", "€"
    var consumption: Double
}

@MainActor
final class UtilityService: ObservableObject {
    @Published var entries: [UtilityEntry] = []
    private let key = "prvio.utilities"

    init() { load() }

    func load() {
        if let d = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([UtilityEntry].self, from: d) {
            entries = decoded.sorted { $0.month > $1.month }
        }
    }

    func add(_ e: UtilityEntry) { entries.insert(e, at: 0); entries.sort { $0.month > $1.month }; save() }
    func delete(_ e: UtilityEntry) { entries.removeAll { $0.id == e.id }; save() }

    func entriesFor(_ type: String) -> [UtilityEntry] { entries.filter { $0.type == type }.sorted { $0.month < $1.month } }
    func lastSixMonths(_ type: String) -> [UtilityEntry] { Array(entriesFor(type).suffix(6)) }

    func totalFor(_ type: String) -> Double { entriesFor(type).map(\.amount).reduce(0, +) }
    func currentMonthEntry(_ type: String) -> UtilityEntry? {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"
        let current = f.string(from: Date())
        return entriesFor(type).first { $0.month == current }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(entries) { UserDefaults.standard.set(d, forKey: key) }
    }
}

// MARK: - Main View

struct UtilityView: View {
    @StateObject private var service = UtilityService()
    @State private var showAdd = false
    @State private var selectedType = "electricity"

    let types: [(id: String, icon: String, color: Color, label: String, unit: String)] = [
        ("electricity", "bolt.fill",      .yellow,                                  "Electricity", "kWh"),
        ("water",       "drop.fill",      .blue,                                    "Water",       "m³"),
        ("gas",         "flame.fill",     .orange,                                  "Gas",         "m³"),
        ("internet",    "wifi",           Color(red: 0.3, green: 0.85, blue: 0.5), "Internet",    "Mbps"),
    ]

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                PageHeader(title: "Utilities",
                           trailing: AnyView(
                            Button {
                                showAdd = true
                                HapticFeedback.impact(.medium)
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(.primary)
                            }
                           ))
                    .padding(.bottom, 12)

                // Summary cards
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(types, id: \.id) { t in
                            UtilitySummaryCard(
                                type: t,
                                currentEntry: service.currentMonthEntry(t.id),
                                isSelected: selectedType == t.id
                            )
                            .onTapGesture {
                                HapticFeedback.selection()
                                withAnimation(.spring(response: 0.25)) { selectedType = t.id }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 16)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        let typeData = service.lastSixMonths(selectedType)
                        let current = types.first { $0.id == selectedType }

                        if typeData.count >= 2 {
                            chartCard(data: typeData, color: current?.color ?? .white, unit: current?.unit ?? "")
                        }

                        // Monthly totals summary
                        if !typeData.isEmpty {
                            totalsCard(data: service.entriesFor(selectedType), color: current?.color ?? .white)
                        }

                        if typeData.isEmpty {
                            emptyState(type: current)
                        } else {
                            ForEach(service.entriesFor(selectedType).reversed()) { entry in
                                UtilityEntryRow(entry: entry, color: current?.color ?? .white)
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            HapticFeedback.warning()
                                            service.delete(entry)
                                        } label: { Label("Delete", systemImage: "trash") }
                                    }
                            }
                        }
                    }
                    .padding(.horizontal, 20).padding(.bottom, 110)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAdd) {
            AddUtilitySheet(defaultType: selectedType) { entry in service.add(entry) }
        }
    }

    private func chartCard(data: [UtilityEntry], color: Color, unit: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Last \(data.count) months")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.6))
                Chart(data, id: \.id) { e in
                    BarMark(
                        x: .value("Month", String(e.month.suffix(2))),
                        y: .value("€", e.amount)
                    )
                    .foregroundStyle(color.opacity(0.75))
                    .cornerRadius(6)
                    .annotation(position: .top) {
                        Text("€\(String(format: "%.0f", e.amount))")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.primary.opacity(0.5))
                    }
                }
                .frame(height: 130)
                .chartXAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(.secondary) } }
                .chartYAxis { AxisMarks { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.primary.opacity(0.06))
                    AxisValueLabel().foregroundStyle(.secondary)
                }}
                HStack {
                    let avg = data.map(\.amount).reduce(0, +) / Double(data.count)
                    let totalConsumption = data.map(\.consumption).reduce(0, +)
                    Label("Avg €\(String(format: "%.0f", avg))/mo", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if totalConsumption > 0 {
                        Label("\(String(format: "%.0f", totalConsumption)) \(unit) total", systemImage: "sum")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func totalsCard(data: [UtilityEntry], color: Color) -> some View {
        GlassCard {
            HStack(spacing: 0) {
                statCell(title: "This Year", value: "€\(String(format: "%.0f", data.filter { $0.month.hasPrefix(currentYear) }.map(\.amount).reduce(0, +)))", color: color)
                Divider().background(Color.primary.opacity(0.08)).frame(height: 36)
                statCell(title: "All Time", value: "€\(String(format: "%.0f", data.map(\.amount).reduce(0, +)))", color: color)
                Divider().background(Color.primary.opacity(0.08)).frame(height: 36)
                statCell(title: "Bills", value: "\(data.count)", color: color)
            }
        }
    }

    private func statCell(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 16, weight: .bold)).foregroundStyle(color)
            Text(title).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
    }

    private var currentYear: String {
        let f = DateFormatter(); f.dateFormat = "yyyy"; return f.string(from: Date())
    }

    private func emptyState(type: (id: String, icon: String, color: Color, label: String, unit: String)?) -> some View {
        VStack(spacing: 14) {
            Spacer(minLength: 40)
            Image(systemName: type?.icon ?? "bolt.fill")
                .font(.system(size: 44)).foregroundStyle(Color.primary.opacity(0.18))
            Text("No \(type?.label ?? "") bills yet")
                .font(.system(size: 16)).foregroundStyle(Color.primary.opacity(0.45))
            Text("Tap + to add manually or scan an invoice to extract data automatically.")
                .font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.3))
                .multilineTextAlignment(.center).padding(.horizontal, 32)
            Spacer(minLength: 40)
        }
    }
}

// MARK: - Summary Card

private struct UtilitySummaryCard: View {
    let type: (id: String, icon: String, color: Color, label: String, unit: String)
    let currentEntry: UtilityEntry?
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: type.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? .black : type.color)
                Text(type.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? .black : .white)
            }
            if let entry = currentEntry {
                Text("€\(String(format: "%.2f", entry.amount))")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(isSelected ? .black : type.color)
                if entry.consumption > 0 {
                    Text("\(String(format: "%.0f", entry.consumption)) \(type.unit)")
                        .font(.system(size: 10))
                        .foregroundStyle(isSelected ? .black.opacity(0.6) : Color.primary.opacity(0.4))
                }
            } else {
                Text("No data")
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? .black.opacity(0.5) : Color.primary.opacity(0.3))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(isSelected ? type.color : Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isSelected ? .clear : type.color.opacity(0.25), lineWidth: 1)
        )
        .animation(.spring(response: 0.2), value: isSelected)
    }
}

// MARK: - Entry Row

private struct UtilityEntryRow: View {
    let entry: UtilityEntry
    let color: Color
    var displayMonth: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"
        guard let d = f.date(from: entry.month) else { return entry.month }
        let out = DateFormatter(); out.dateFormat = "MMMM yyyy"; return out.string(from: d)
    }
    var body: some View {
        GlassCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(displayMonth)
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.primary)
                    if entry.consumption > 0 {
                        Text("\(String(format: "%.0f", entry.consumption)) \(entry.unit)")
                            .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.4))
                    }
                }
                Spacer()
                Text("€\(String(format: "%.2f", entry.amount))")
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(color)
            }
        }
    }
}

// MARK: - Add Sheet with Scan

struct AddUtilitySheet: View {
    let defaultType: String
    let onSave: (UtilityEntry) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var type: String
    @State private var amount = ""
    @State private var consumption = ""
    @State private var month = Date()
    @State private var isScanning = false
    @State private var scanPhotoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var scannedImage: UIImage?
    @State private var isProcessing = false
    @State private var scanResult: String?

    private let types = ["electricity", "water", "gas", "internet", "other"]
    private let units = ["electricity": "kWh", "water": "m³", "gas": "m³", "internet": "Mbps", "other": "units"]

    init(defaultType: String, onSave: @escaping (UtilityEntry) -> Void) {
        self.defaultType = defaultType; self.onSave = onSave
        _type = State(initialValue: defaultType)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        // Scan button
                        scanSection

                        if let result = scanResult {
                            scanResultBanner(result)
                        }

                        GlassCard {
                            HStack {
                                Text("Type").font(.system(size: 15)).foregroundStyle(.primary)
                                Spacer()
                                Picker("", selection: $type) {
                                    ForEach(types, id: \.self) { Text($0.capitalized).tag($0) }
                                }.tint(Color.primary.opacity(0.5))
                            }
                        }

                        GlassCard {
                            VStack(spacing: 0) {
                                HStack {
                                    Text("Amount (€)").font(.system(size: 15)).foregroundStyle(.primary)
                                    Spacer()
                                    TextField("0.00", text: $amount)
                                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(.primary)
                                        .tint(.blue).keyboardType(.decimalPad)
                                        .multilineTextAlignment(.trailing).frame(width: 100)
                                }.padding(.vertical, 4)
                                Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5)
                                HStack {
                                    Text("Consumption (\(units[type] ?? "units"))").font(.system(size: 15)).foregroundStyle(.primary)
                                    Spacer()
                                    TextField("0", text: $consumption)
                                        .font(.system(size: 16)).foregroundStyle(.primary)
                                        .tint(.blue).keyboardType(.decimalPad)
                                        .multilineTextAlignment(.trailing).frame(width: 100)
                                }.padding(.vertical, 4)
                                Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5)
                                DatePicker("Month", selection: $month, displayedComponents: [.date])
                                    .font(.system(size: 15)).foregroundStyle(.primary).tint(.blue)
                            }
                        }
                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 20).padding(.top, 8)
                }
            }
            .navigationTitle("Add Bill").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.primary.opacity(0.7))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let f = DateFormatter(); f.dateFormat = "yyyy-MM"
                        let entry = UtilityEntry(
                            type: type,
                            amount: Double(amount.replacingOccurrences(of: ",", with: ".")) ?? 0,
                            month: f.string(from: month),
                            unit: units[type] ?? "units",
                            consumption: Double(consumption.replacingOccurrences(of: ",", with: ".")) ?? 0
                        )
                        onSave(entry); HapticFeedback.success(); dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(amount.isEmpty ? Color.primary.opacity(0.3) : Color.blue)
                    .disabled(amount.isEmpty)
                }
            }
        }
        .photosPicker(isPresented: $isScanning, selection: $scanPhotoItem, matching: .images)
        .onChange(of: scanPhotoItem) { _, item in
            guard let item else { return }
            Task { await processPickedPhoto(item) }
        }
        .sheet(isPresented: $showCamera) {
            CameraCapture { image in
                scannedImage = image
                Task { await runOCR(on: image) }
            }
        }
    }

    private var scanSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Menu {
                    Button {
                        showCamera = true
                    } label: {
                        Label("Take Photo", systemImage: "camera.fill")
                    }
                    Button {
                        isScanning = true
                    } label: {
                        Label("Choose from Library", systemImage: "photo.on.rectangle")
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isProcessing {
                            ProgressView().tint(.white).scaleEffect(0.8)
                            Text("Scanning…")
                        } else {
                            Image(systemName: "doc.text.viewfinder")
                                .font(.system(size: 18, weight: .semibold))
                            Text("Scan Invoice")
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [.blue.opacity(0.7), .purple.opacity(0.7)],
                            startPoint: .leading, endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isProcessing)
            }
            Text("Auto-extracts amount, consumption, and month from your bill")
                .font(.system(size: 11))
                .foregroundStyle(Color.primary.opacity(0.35))
        }
    }

    private func scanResultBanner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text(text).font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.7))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.green.opacity(0.25), lineWidth: 0.5))
    }

    // MARK: - OCR

    private func processPickedPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data) else { return }
        scannedImage = uiImage
        await runOCR(on: uiImage)
    }

    private func runOCR(on image: UIImage) async {
        isProcessing = true
        defer { isProcessing = false }

        guard let cgImage = image.cgImage else { return }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        try? handler.perform([request])

        let observations = request.results ?? []
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        let fullText = lines.joined(separator: "\n").lowercased()

        await MainActor.run {
            parseInvoiceText(fullText, lines: lines)
        }
    }

    private func parseInvoiceText(_ text: String, lines: [String]) {
        var found: [String] = []

        // Detect utility type
        if text.contains("electricitat") || text.contains("curent") || text.contains("energie electric") || text.contains("kwh") {
            type = "electricity"
            found.append("electricity")
        } else if text.contains("gaz") || text.contains("gas") || text.contains("metan") {
            type = "gas"
            found.append("gas")
        } else if text.contains("apă") || text.contains("apa") || text.contains("water") || text.contains("canal") {
            type = "water"
            found.append("water")
        } else if text.contains("internet") || text.contains("broadband") || text.contains("fiber") || text.contains("digi") || text.contains("vodafone") || text.contains("orange") || text.contains("telekom") {
            type = "internet"
            found.append("internet")
        }

        // Detect amount (look for currency patterns)
        let amountPatterns = [
            #"total[^\d]*(\d+[\.,]\d{2})"#,
            #"de plată[^\d]*(\d+[\.,]\d{2})"#,
            #"suma[^\d]*(\d+[\.,]\d{2})"#,
            #"(\d+[\.,]\d{2})\s*(?:ron|lei|eur|€)"#,
            #"€\s*(\d+[\.,]\d{2})"#,
        ]
        for pattern in amountPatterns {
            if let match = text.firstMatch(pattern: pattern) {
                amount = match.replacingOccurrences(of: ",", with: ".")
                found.append("amount €\(amount)")
                break
            }
        }

        // Detect consumption
        let consumptionPatterns = [
            #"(\d+[\.,]?\d*)\s*kwh"#,
            #"(\d+[\.,]?\d*)\s*m[c³3]"#,
            #"consum[^\d]*(\d+[\.,]?\d*)"#,
            #"quantity[^\d]*(\d+[\.,]?\d*)"#,
        ]
        for pattern in consumptionPatterns {
            if let match = text.firstMatch(pattern: pattern) {
                consumption = match.replacingOccurrences(of: ",", with: ".")
                let unit = text.contains("kwh") ? "kWh" : "m³"
                found.append("\(consumption) \(unit)")
                break
            }
        }

        // Detect month/date
        let romanianMonths = ["ianuarie": 1, "februarie": 2, "martie": 3, "aprilie": 4,
                              "mai": 5, "iunie": 6, "iulie": 7, "august": 8,
                              "septembrie": 9, "octombrie": 10, "noiembrie": 11, "decembrie": 12]
        let cal = Calendar.current
        var detectedMonth: Date?

        for (name, num) in romanianMonths {
            if text.contains(name) {
                // look for year near the month name
                let yearPattern = #"(\d{4})"#
                if let yearStr = text.firstMatch(pattern: yearPattern), let year = Int(yearStr) {
                    var comps = DateComponents(); comps.year = year; comps.month = num; comps.day = 1
                    detectedMonth = cal.date(from: comps)
                } else {
                    var comps = DateComponents()
                    comps.year = cal.component(.year, from: Date())
                    comps.month = num; comps.day = 1
                    detectedMonth = cal.date(from: comps)
                }
                break
            }
        }

        // Also try MM/YYYY or YYYY-MM patterns
        if detectedMonth == nil {
            let datePatterns = [#"(\d{2})[/\-\.](\d{4})"#, #"(\d{4})[/\-\.](\d{2})"#]
            for pattern in datePatterns {
                if let m = text.range(of: pattern, options: .regularExpression) {
                    let part = String(text[m])
                    let nums = part.components(separatedBy: CharacterSet(charactersIn: "/-."))
                        .compactMap { Int($0) }
                    if nums.count == 2 {
                        let (y, mo) = nums[0] > 1000 ? (nums[0], nums[1]) : (nums[1], nums[0])
                        if mo >= 1 && mo <= 12 && y >= 2000 {
                            var comps = DateComponents(); comps.year = y; comps.month = mo; comps.day = 1
                            detectedMonth = cal.date(from: comps)
                            break
                        }
                    }
                }
            }
        }

        if let d = detectedMonth {
            month = d
            let f = DateFormatter(); f.dateFormat = "MMMM yyyy"
            found.append(f.string(from: d))
        }

        if !found.isEmpty {
            scanResult = "Detected: \(found.joined(separator: " · "))"
        } else {
            scanResult = "Could not extract data automatically — please fill in manually."
        }
    }
}

// MARK: - String regex helper

private extension String {
    func firstMatch(pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(startIndex..., in: self)
        guard let match = regex.firstMatch(in: self, range: range) else { return nil }
        // return last capture group
        for i in stride(from: match.numberOfRanges - 1, through: 1, by: -1) {
            let r = match.range(at: i)
            if let swiftRange = Range(r, in: self) {
                return String(self[swiftRange])
            }
        }
        return nil
    }
}

// MARK: - Camera Capture

struct CameraCapture: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraCapture
        init(_ parent: CameraCapture) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onCapture(img) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
