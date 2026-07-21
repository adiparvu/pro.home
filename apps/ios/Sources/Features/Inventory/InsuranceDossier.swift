import SwiftUI
import UIKit

// MARK: - Insurance dossier PDF
//
// The document you hand an insurer or keep in the family archive: the
// property's identity (photo, address, type, size, ownership and renovation
// history), a figures summary, the full inventory with purchase/warranty
// detail per item, and the supporting documents on record (policies,
// warranties, invoices, contracts) with their reference numbers and expiry.
//
// Same rendering school as InventoryExport/PlantPDFExporter: A4,
// UIGraphicsPDFRenderer, manual page breaks, and the honesty law — a line
// renders only when the data exists; nothing is fabricated to fill space.
// The property photo is fetched asynchronously BEFORE rendering (the PDF
// closure is synchronous), so the entry point is async.

@MainActor
enum InsuranceDossier {

    private static let pageW: CGFloat = 595
    private static let pageH: CGFloat = 842
    private static let margin: CGFloat = 44

    /// Document categories that belong in an insurance dossier.
    private static let relevantDocCategories: Set<String> = [
        "insurance", "warranty", "invoice", "contract", "certificate",
        "permit", "tax", "legal",
    ]

    /// Builds the dossier and returns its temp-file URL. `documents` may hold
    /// the full library — the relevant categories (plus anything marked
    /// critical) are selected here so every caller applies the same policy.
    static func makePDF(items: [InventoryItem],
                        property: PropertyModel?,
                        documents: [DocumentModel]) async -> URL? {
        guard !items.isEmpty || property != nil else { return nil }

        // Pre-fetch the property photo — sync drawing needs the bits in hand.
        var propertyPhoto: UIImage?
        if let s = property?.photoUrl, let u = URL(string: s),
           let (data, _) = try? await URLSession.shared.data(from: u) {
            propertyPhoto = UIImage(data: data)
        }

        let docs = documents
            .filter { relevantDocCategories.contains($0.category) || $0.isCritical }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        // Phase 2 annexes — the EVIDENCE, not just the list:
        // (a) receipt photos stored on-device per item (purchase proof);
        // (b) each relevant document's first page (signed fetch; PDFs are
        //     rasterised, images pass through). Failures skip silently — an
        //     annex page never fabricates.
        let receipts: [(String, UIImage)] = items.compactMap { item in
            InventoryImageStore.loadReceipt(for: item.id).map { (item.name, $0) }
        }
        var docPages: [(String, UIImage)] = []
        for doc in docs {
            guard let url = await DocumentFilesService.resolve(doc.fileUrl),
                  let (data, _) = try? await URLSession.shared.data(from: url) else { continue }
            let isPDF = doc.mimeType == "application/pdf"
                || doc.fileName.lowercased().hasSuffix(".pdf")
            if isPDF {
                if let img = firstPDFPageImage(data) { docPages.append((doc.name, img)) }
            } else if let img = UIImage(data: data) {
                docPages.append((doc.name, img))
            }
        }

        return render(items: items, property: property,
                      propertyPhoto: propertyPhoto, documents: docs,
                      receipts: receipts, docPages: docPages)
    }

    /// First page of a PDF rendered to an image (annex-quality, ~2× A4 width).
    private static func firstPDFPageImage(_ data: Data) -> UIImage? {
        guard let provider = CGDataProvider(data: data as CFData),
              let pdf = CGPDFDocument(provider),
              let page = pdf.page(at: 1) else { return nil }
        let box = page.getBoxRect(.mediaBox)
        guard box.width > 0, box.height > 0 else { return nil }
        let scale = 1100 / box.width
        let size = CGSize(width: box.width * scale, height: box.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.cgContext.translateBy(x: 0, y: size.height)
            ctx.cgContext.scaleBy(x: scale, y: -scale)
            ctx.cgContext.translateBy(x: -box.minX, y: -box.minY)
            ctx.cgContext.drawPDFPage(page)
        }
    }

    // MARK: - Rendering

    private static func render(items: [InventoryItem],
                               property: PropertyModel?,
                               propertyPhoto: UIImage?,
                               documents: [DocumentModel],
                               receipts: [(String, UIImage)] = [],
                               docPages: [(String, UIImage)] = []) -> URL? {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageW, height: pageH))
        let title = String(localized: "inv_dossier_title")
        let safeName = title.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName.isEmpty ? "dossier" : safeName).pdf")

        let contentW = pageW - margin * 2
        let money = { (v: Double) in CurrencyService.money(v, code: "EUR", whole: true) }
        let groups = grouped(items)

        do {
            try renderer.writePDF(to: url) { ctx in
                ctx.beginPage()
                var y = margin

                func ensureRoom(_ needed: CGFloat) {
                    if y + needed > pageH - margin {
                        ctx.beginPage()
                        y = margin
                    }
                }

                func drawText(_ s: String, font: UIFont, color: UIColor = .black,
                              x: CGFloat = margin, width: CGFloat? = nil,
                              align: NSTextAlignment = .natural, gap: CGFloat = 6) {
                    let para = NSMutableParagraphStyle()
                    para.alignment = align
                    let attr: [NSAttributedString.Key: Any] = [
                        .font: font, .foregroundColor: color, .paragraphStyle: para]
                    let w = width ?? contentW
                    let bounding = (s as NSString).boundingRect(
                        with: CGSize(width: w, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin], attributes: attr, context: nil)
                    ensureRoom(bounding.height + gap)
                    (s as NSString).draw(in: CGRect(x: x, y: y, width: w, height: bounding.height + 2),
                                         withAttributes: attr)
                    y += bounding.height + gap
                }

                func sectionHeader(_ s: String) {
                    ensureRoom(40)
                    y += 8
                    drawText(s.uppercased(), font: .boldSystemFont(ofSize: 12),
                             color: .darkGray, gap: 8)
                    ctx.cgContext.setStrokeColor(UIColor(white: 0, alpha: 0.15).cgColor)
                    ctx.cgContext.setLineWidth(0.7)
                    ctx.cgContext.move(to: CGPoint(x: margin, y: y - 4))
                    ctx.cgContext.addLine(to: CGPoint(x: pageW - margin, y: y - 4))
                    ctx.cgContext.strokePath()
                }

                // ---- Header + property identity ----
                drawText(title, font: .boldSystemFont(ofSize: 22), gap: 4)
                drawText(String(format: String(localized: "inv_report_generated"),
                                Date().formatted(date: .long, time: .omitted)),
                         font: .systemFont(ofSize: 10), color: .gray, gap: 12)

                if let photo = propertyPhoto {
                    let h: CGFloat = 150
                    ensureRoom(h + 12)
                    let rect = CGRect(x: margin, y: y, width: contentW, height: h)
                    ctx.cgContext.saveGState()
                    UIBezierPath(roundedRect: rect, cornerRadius: 8).addClip()
                    let scale = max(rect.width / max(photo.size.width, 1),
                                    rect.height / max(photo.size.height, 1))
                    let w = photo.size.width * scale, ph = photo.size.height * scale
                    photo.draw(in: CGRect(x: rect.midX - w / 2, y: rect.midY - ph / 2,
                                          width: w, height: ph))
                    ctx.cgContext.restoreGState()
                    y += h + 12
                }

                if let p = property {
                    sectionHeader(String(localized: "inv_dossier_property"))
                    drawText(p.name, font: .boldSystemFont(ofSize: 15), gap: 4)
                    let address = [p.addressLine1, p.city, p.postalCode ?? "", p.country]
                        .filter { !$0.isEmpty }.joined(separator: ", ")
                    if !address.isEmpty {
                        drawText(address, font: .systemFont(ofSize: 11), color: .darkGray, gap: 4)
                    }
                    var facts: [String] = []
                    if !p.propertyType.isEmpty { facts.append(p.propertyType.capitalized) }
                    if let sqm = p.sizeSqm, sqm > 0 { facts.append(String(format: "%.0f m²", sqm)) }
                    if let rooms = p.numRooms, rooms > 0 {
                        facts.append(String(format: String(localized: "inv_dossier_rooms_fmt"), rooms))
                    }
                    if let year = p.yearBuilt, year > 0 {
                        facts.append(String(format: String(localized: "inv_dossier_year_built_fmt"), year))
                    }
                    if !facts.isEmpty {
                        drawText(facts.joined(separator: " · "),
                                 font: .systemFont(ofSize: 11), color: .darkGray, gap: 4)
                    }
                    if let owners = p.owners, !owners.isEmpty {
                        let line = owners.map { o -> String in
                            let span = o.yearTo.map { "\(o.yearFrom)–\($0)" } ?? "\(o.yearFrom)–"
                            return "\(o.name) (\(span))"
                        }.joined(separator: ", ")
                        drawText("\(String(localized: "inv_dossier_owners")): \(line)",
                                 font: .systemFont(ofSize: 10), color: .gray, gap: 4)
                    }
                    if let ren = p.renovations, !ren.isEmpty {
                        let line = ren.map { r -> String in
                            let span = r.yearTo.map { "\(r.yearFrom)–\($0)" } ?? "\(r.yearFrom)"
                            return "\(r.title) (\(span))"
                        }.joined(separator: ", ")
                        drawText("\(String(localized: "inv_dossier_renovations")): \(line)",
                                 font: .systemFont(ofSize: 10), color: .gray, gap: 4)
                    }
                }

                // ---- Figures summary ----
                sectionHeader(String(localized: "inv_dossier_summary"))
                var lines: [String] = []
                lines.append(String(format: String(localized: "inv_dossier_items_fmt"), items.count))
                let total = items.reduce(0) { $0 + $1.purchasePrice }
                if total > 0 {
                    lines.append("\(String(localized: "inv_dossier_total_value")): \(money(total))")
                }
                let activeWarranties = items.filter {
                    $0.warrantyStatus == .valid || $0.warrantyStatus == .expiringSoon
                }.count
                if activeWarranties > 0 {
                    lines.append(String(format: String(localized: "inv_dossier_warranties_fmt"),
                                        activeWarranties))
                }
                if !documents.isEmpty {
                    lines.append(String(format: String(localized: "inv_dossier_docs_fmt"),
                                        documents.count))
                }
                drawText(lines.joined(separator: " · "),
                         font: .systemFont(ofSize: 11), color: .darkGray, gap: 6)

                // ---- Inventory, grouped by category ----
                if !items.isEmpty {
                    sectionHeader(String(localized: "inv_dossier_section_inventory"))
                }
                for group in groups {
                    ensureRoom(70)
                    y += 2
                    let headerY = y
                    drawText(InventoryLabels.category(group.category),
                             font: .boldSystemFont(ofSize: 11), color: .darkGray, gap: 6)
                    if group.subtotal > 0 {
                        let saved = y; y = headerY
                        drawText(money(group.subtotal), font: .boldSystemFont(ofSize: 11),
                                 color: .darkGray, align: .right, gap: 0)
                        y = saved
                    }

                    for item in group.items {
                        let rowH: CGFloat = 52
                        ensureRoom(rowH)
                        let rowTop = y
                        var textX = margin

                        if let photo = InventoryImageStore.load(for: item.id) {
                            ctx.cgContext.saveGState()
                            let rect = CGRect(x: margin, y: rowTop + 2, width: 40, height: 40)
                            UIBezierPath(roundedRect: rect, cornerRadius: 5).addClip()
                            let scale = max(rect.width / max(photo.size.width, 1),
                                            rect.height / max(photo.size.height, 1))
                            let w = photo.size.width * scale, h = photo.size.height * scale
                            photo.draw(in: CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2,
                                                  width: w, height: h))
                            ctx.cgContext.restoreGState()
                            textX += 50
                        }

                        let valueW: CGFloat = 90
                        let nameW = pageW - margin - textX - valueW - 8
                        ((item.name.replacingOccurrences(of: "\n", with: " ")) as NSString).draw(
                            in: CGRect(x: textX, y: rowTop + 3, width: nameW, height: 14),
                            withAttributes: [.font: UIFont.boldSystemFont(ofSize: 11),
                                             .foregroundColor: UIColor.black])

                        var line1: [String] = []
                        if !item.brand.isEmpty { line1.append(item.brand) }
                        line1.append(InventoryLabels.location(item.location))
                        if !item.serialNumber.isEmpty {
                            line1.append("\(String(localized: "Serial")): \(item.serialNumber)")
                        }
                        (line1.joined(separator: " · ") as NSString).draw(
                            in: CGRect(x: textX, y: rowTop + 19, width: nameW, height: 12),
                            withAttributes: [.font: UIFont.systemFont(ofSize: 9),
                                             .foregroundColor: UIColor.gray])

                        // Purchase + warranty line — the insurer's evidence row.
                        var line2: [String] = []
                        if let d = item.purchaseDate {
                            line2.append(String(format: String(localized: "inv_dossier_purchased_fmt"),
                                                d.formatted(date: .abbreviated, time: .omitted)))
                        }
                        if let w = item.warrantyExpiresAt {
                            line2.append(String(format: String(localized: "inv_dossier_warranty_until_fmt"),
                                                w.formatted(date: .abbreviated, time: .omitted)))
                        }
                        if !line2.isEmpty {
                            (line2.joined(separator: " · ") as NSString).draw(
                                in: CGRect(x: textX, y: rowTop + 33, width: nameW, height: 12),
                                withAttributes: [.font: UIFont.systemFont(ofSize: 9),
                                                 .foregroundColor: UIColor.gray])
                        }

                        let para = NSMutableParagraphStyle(); para.alignment = .right
                        ((item.purchasePrice > 0 ? money(item.purchasePrice) : "—") as NSString).draw(
                            in: CGRect(x: pageW - margin - valueW, y: rowTop + 3,
                                       width: valueW, height: 14),
                            withAttributes: [.font: UIFont.systemFont(ofSize: 11),
                                             .foregroundColor: item.purchasePrice > 0
                                                ? UIColor.black : UIColor.lightGray,
                                             .paragraphStyle: para])

                        y = rowTop + rowH
                        ctx.cgContext.setStrokeColor(UIColor(white: 0, alpha: 0.06).cgColor)
                        ctx.cgContext.setLineWidth(0.5)
                        ctx.cgContext.move(to: CGPoint(x: margin, y: y - 3))
                        ctx.cgContext.addLine(to: CGPoint(x: pageW - margin, y: y - 3))
                        ctx.cgContext.strokePath()
                    }
                }

                // ---- Supporting documents ----
                if !documents.isEmpty {
                    sectionHeader(String(localized: "inv_dossier_section_documents"))
                    for doc in documents {
                        let rowH: CGFloat = 34
                        ensureRoom(rowH)
                        let rowTop = y
                        (doc.name.replacingOccurrences(of: "\n", with: " ") as NSString).draw(
                            in: CGRect(x: margin, y: rowTop + 2, width: contentW, height: 14),
                            withAttributes: [.font: UIFont.boldSystemFont(ofSize: 10),
                                             .foregroundColor: UIColor.black])
                        var detail: [String] = [DocumentTypeDisplay.name(doc.category)]
                        if let issuer = doc.issuerCompany, !issuer.isEmpty { detail.append(issuer) }
                        if let policy = doc.policyNumber, !policy.isEmpty {
                            detail.append(String(format: String(localized: "inv_dossier_policy_fmt"), policy))
                        }
                        if let v = doc.value, v > 0 {
                            detail.append(CurrencyService.money(v, code: doc.currency ?? "EUR", whole: true))
                        }
                        if let exp = doc.expiresDisplay {
                            detail.append(String(format: String(localized: "inv_dossier_expires_fmt"), exp))
                        }
                        (detail.joined(separator: " · ") as NSString).draw(
                            in: CGRect(x: margin, y: rowTop + 17, width: contentW, height: 12),
                            withAttributes: [.font: UIFont.systemFont(ofSize: 9),
                                             .foregroundColor: UIColor.gray])
                        y = rowTop + rowH
                    }
                }

                // ---- Annex: receipts (purchase evidence) ----
                func drawAnnexImage(_ caption: String, _ image: UIImage) {
                    let maxH: CGFloat = 300
                    let ratio = image.size.height / max(image.size.width, 1)
                    let w = min(contentW, maxH / max(ratio, 0.001))
                    let h = w * ratio
                    ensureRoom(h + 30)
                    (caption as NSString).draw(
                        in: CGRect(x: margin, y: y, width: contentW, height: 12),
                        withAttributes: [.font: UIFont.boldSystemFont(ofSize: 9),
                                         .foregroundColor: UIColor.darkGray])
                    y += 16
                    ctx.cgContext.saveGState()
                    let rect = CGRect(x: margin, y: y, width: w, height: h)
                    UIBezierPath(roundedRect: rect, cornerRadius: 6).addClip()
                    image.draw(in: rect)
                    ctx.cgContext.restoreGState()
                    y += h + 14
                }
                if !receipts.isEmpty {
                    sectionHeader(String(localized: "inv_dossier_annex_receipts"))
                    for (name, image) in receipts { drawAnnexImage(name, image) }
                }

                // ---- Annex: document first pages ----
                if !docPages.isEmpty {
                    sectionHeader(String(localized: "inv_dossier_annex_docs"))
                    for (name, image) in docPages { drawAnnexImage(name, image) }
                }

                // ---- Grand total ----
                if total > 0 {
                    y += 8
                    ensureRoom(40)
                    ctx.cgContext.setStrokeColor(UIColor(white: 0, alpha: 0.3).cgColor)
                    ctx.cgContext.setLineWidth(1)
                    ctx.cgContext.move(to: CGPoint(x: margin, y: y))
                    ctx.cgContext.addLine(to: CGPoint(x: pageW - margin, y: y))
                    ctx.cgContext.strokePath()
                    y += 8
                    drawText("\(String(localized: "inv_report_grand_total")): \(money(total))",
                             font: .boldSystemFont(ofSize: 13), align: .right, gap: 0)
                }
            }
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Grouping (canonical category order, A→Z inside)

    private struct CategoryGroup {
        let category: String
        let items: [InventoryItem]
        var subtotal: Double { items.reduce(0) { $0 + $1.purchasePrice } }
    }

    private static func grouped(_ items: [InventoryItem]) -> [CategoryGroup] {
        let byCategory = Dictionary(grouping: items, by: \.category)
        let known = InventoryCatalog.categories.filter { byCategory[$0] != nil }
        let extra = byCategory.keys.filter { !InventoryCatalog.categories.contains($0) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return (known + extra).map { cat in
            CategoryGroup(category: cat,
                          items: byCategory[cat]!.sorted {
                              $0.name.localizedStandardCompare($1.name) == .orderedAscending
                          })
        }
    }
}
