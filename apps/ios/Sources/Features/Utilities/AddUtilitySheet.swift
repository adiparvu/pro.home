import SwiftUI
import Vision
import PhotosUI

// MARK: - Add Sheet with Scan

struct AddUtilitySheet: View {
    let defaultType: String
    let propertyId: UUID?
    let onSave: (NewUtilityEntry) -> Void
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

    init(defaultType: String, propertyId: UUID?, onSave: @escaping (NewUtilityEntry) -> Void) {
        self.defaultType = defaultType
        self.propertyId = propertyId
        self.onSave = onSave
        _type = State(initialValue: defaultType)
    }

    var body: some View {
        FormScaffold(title: "Add Bill",
                     canSave: !amount.isEmpty,
                     error: .constant(nil),
                     onSave: {
            guard let pid = propertyId else { dismiss(); return }
            let readingDate = AppDate.dayString(from: month)
            let appUnit = units[type] ?? "other"
            let entry = NewUtilityEntry(
                propertyId: pid,
                appCategory: type,
                meterType: UtilityService.meterType(for: type),
                readingDate: readingDate,
                readingValue: Double(consumption.replacingOccurrences(of: ",", with: ".")) ?? 0,
                unit: UtilityService.dbUnit(for: appUnit),
                cost: Double(amount.replacingOccurrences(of: ",", with: "."))
            )
            onSave(entry); HapticFeedback.success(); dismiss()
        }) {
            scanSection

            if let result = scanResult {
                scanResultBanner(result)
            }

            GlassCard {
                HStack {
                    Text("Type").font(.system(size: 15)).foregroundStyle(.primary)
                    Spacer()
                    Picker("", selection: $type) {
                        ForEach(types, id: \.self) { Text(LocalizedStringKey($0.capitalized)).tag($0) }
                    }.tint(Color.primary.opacity(AppOpacity.mediumText))
                }
            }

            GlassCard {
                VStack(spacing: 0) {
                    HStack {
                        Text("Amount (€)").font(.system(size: 15)).foregroundStyle(.primary)
                        Spacer()
                        TextField("0.00", text: $amount)
                            .font(AppFont.headline).foregroundStyle(.primary)
                            .tint(.accentColor).keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing).frame(width: 100)
                    }.padding(.vertical, AppSpacing.xxs)
                    Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5)
                    HStack {
                        Text("Consumption (\(units[type] ?? "units"))").font(.system(size: 15)).foregroundStyle(.primary)
                        Spacer()
                        TextField("0", text: $consumption)
                            .font(.system(size: 16)).foregroundStyle(.primary)
                            .tint(.accentColor).keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing).frame(width: 100)
                    }.padding(.vertical, AppSpacing.xxs)
                    Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5)
                    DatePicker("Month", selection: $month, displayedComponents: [.date])
                        .font(.system(size: 15)).foregroundStyle(.primary).tint(.accentColor)
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
                                .font(AppFont.title3)
                            Text("Scan Invoice")
                                .font(AppFont.subheadline)
                        }
                    }
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.base)
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
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
        }
    }

    private func scanResultBanner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text(text).font(.system(size: 12)).foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
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

        if text.contains("electricitat") || text.contains("curent") || text.contains("energie electric") || text.contains("kwh") {
            type = "electricity"; found.append("electricity")
        } else if text.contains("gaz") || text.contains("gas") || text.contains("metan") {
            type = "gas"; found.append("gas")
        } else if text.contains("apă") || text.contains("apa") || text.contains("water") || text.contains("canal") {
            type = "water"; found.append("water")
        } else if text.contains("internet") || text.contains("broadband") || text.contains("fiber") || text.contains("digi") || text.contains("vodafone") || text.contains("orange") || text.contains("telekom") {
            type = "internet"; found.append("internet")
        }

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

        let romanianMonths = ["ianuarie": 1, "februarie": 2, "martie": 3, "aprilie": 4,
                              "mai": 5, "iunie": 6, "iulie": 7, "august": 8,
                              "septembrie": 9, "octombrie": 10, "noiembrie": 11, "decembrie": 12]
        let cal = Calendar.current
        var detectedMonth: Date?

        for (name, num) in romanianMonths {
            if text.contains(name) {
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
            scanResult = String(format: String(localized: "Detected: %@"), found.joined(separator: " · "))
        } else {
            scanResult = String(localized: "Could not extract data automatically — please fill in manually.")
        }
    }
}

// MARK: - String regex helper

private extension String {
    func firstMatch(pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(startIndex..., in: self)
        guard let match = regex.firstMatch(in: self, range: range) else { return nil }
        for i in stride(from: match.numberOfRanges - 1, through: 1, by: -1) {
            let r = match.range(at: i)
            if let swiftRange = Range(r, in: self) {
                return String(self[swiftRange])
            }
        }
        return nil
    }
}
