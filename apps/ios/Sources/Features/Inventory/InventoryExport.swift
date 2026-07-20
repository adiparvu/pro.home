import SwiftUI
import UIKit

// MARK: - Inventory PDF exports
//
// Two printable documents built from the data the app already holds:
//
// 1. The insurance report — every item with photo thumbnail, name, brand,
//    location, serial and value, grouped by category with subtotals and a
//    grand total. Honesty law: a line renders only when the value exists;
//    missing prices show as "—", never as a fabricated 0.
// 2. A batch QR label sheet — an A4 grid of the same QR codes the per-item
//    sheet shares/prints (same renderer, same content format), with the item
//    name underneath, for labelling a whole garage in one print run.
//
// Mirrors PlantPDFExporter / ElementPDFExporter: UIGraphicsPDFRenderer with
// manual page breaks. MainActor because the QR tiles come out of SwiftUI's
// ImageRenderer, and both entry points run from a button tap anyway.

@MainActor
enum InventoryExport {

    // A4 in PDF points.
    private static let pageW: CGFloat = 595
    private static let pageH: CGFloat = 842
    private static let margin: CGFloat = 44

    // MARK: - Insurance report

    static func makeReportPDF(items: [InventoryItem], propertyName: String?) -> URL? {
        guard !items.isEmpty else { return nil }
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageW, height: pageH))
        let title = String(localized: "inv_report_title")
        let safeName = title.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName.isEmpty ? "inventory" : safeName).pdf")

        let groups = groupedByCategory(items)
        let contentW = pageW - margin * 2

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
                    let attr: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: para]
                    let w = width ?? contentW
                    let bounding = (s as NSString).boundingRect(
                        with: CGSize(width: w, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin], attributes: attr, context: nil)
                    ensureRoom(bounding.height + gap)
                    (s as NSString).draw(in: CGRect(x: x, y: y, width: w, height: bounding.height + 2),
                                         withAttributes: attr)
                    y += bounding.height + gap
                }

                // Header.
                drawText(title, font: .boldSystemFont(ofSize: 22), gap: 4)
                if let propertyName, !propertyName.isEmpty {
                    drawText(propertyName, font: .systemFont(ofSize: 13), color: .darkGray, gap: 4)
                }
                drawText(String(format: String(localized: "inv_report_generated"),
                                Date().formatted(date: .long, time: .omitted)),
                         font: .systemFont(ofSize: 10), color: .gray, gap: 14)

                // Sections.
                let money = { (v: Double) in CurrencyService.money(v, code: "EUR", whole: true) }
                for group in groups {
                    ensureRoom(60)
                    y += 4
                    // Section header: category name left, subtotal right.
                    let headerY = y
                    drawText(InventoryLabels.category(group.category).uppercased(),
                             font: .boldSystemFont(ofSize: 12), color: .darkGray, gap: 8)
                    if group.subtotal > 0 {
                        let saved = y; y = headerY
                        drawText(money(group.subtotal), font: .boldSystemFont(ofSize: 12),
                                 color: .darkGray, align: .right, gap: 0)
                        y = saved
                    }
                    ctx.cgContext.setStrokeColor(UIColor(white: 0, alpha: 0.15).cgColor)
                    ctx.cgContext.setLineWidth(0.7)
                    ctx.cgContext.move(to: CGPoint(x: margin, y: y - 4))
                    ctx.cgContext.addLine(to: CGPoint(x: pageW - margin, y: y - 4))
                    ctx.cgContext.strokePath()

                    for item in group.items {
                        let rowH: CGFloat = 40
                        ensureRoom(rowH)
                        let rowTop = y
                        var textX = margin

                        if let photo = InventoryImageStore.load(for: item.id) {
                            drawThumbnail(photo, in: CGRect(x: margin, y: rowTop + 2, width: 32, height: 32),
                                          cg: ctx.cgContext)
                            textX += 42
                        }

                        // Name (bold) + detail line, leaving room for the value column.
                        let valueW: CGFloat = 90
                        let nameW = pageW - margin - textX - valueW - 8
                        let nameAttr: [NSAttributedString.Key: Any] = [
                            .font: UIFont.boldSystemFont(ofSize: 11), .foregroundColor: UIColor.black]
                        (oneLine(item.name) as NSString).draw(
                            in: CGRect(x: textX, y: rowTop + 4, width: nameW, height: 14), withAttributes: nameAttr)

                        var details: [String] = []
                        if !item.brand.isEmpty { details.append(item.brand) }
                        details.append(InventoryLabels.location(item.location))
                        if !item.serialNumber.isEmpty {
                            details.append("\(String(localized: "Serial")): \(item.serialNumber)")
                        }
                        let detailAttr: [NSAttributedString.Key: Any] = [
                            .font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.gray]
                        (details.joined(separator: " · ") as NSString).draw(
                            in: CGRect(x: textX, y: rowTop + 20, width: nameW, height: 12), withAttributes: detailAttr)

                        // Value column, right-aligned; "—" when no price on record.
                        let para = NSMutableParagraphStyle(); para.alignment = .right
                        let valueAttr: [NSAttributedString.Key: Any] = [
                            .font: UIFont.systemFont(ofSize: 11),
                            .foregroundColor: item.purchasePrice > 0 ? UIColor.black : UIColor.lightGray,
                            .paragraphStyle: para]
                        ((item.purchasePrice > 0 ? money(item.purchasePrice) : "—") as NSString).draw(
                            in: CGRect(x: pageW - margin - valueW, y: rowTop + 4, width: valueW, height: 14),
                            withAttributes: valueAttr)

                        y = rowTop + rowH
                        ctx.cgContext.setStrokeColor(UIColor(white: 0, alpha: 0.06).cgColor)
                        ctx.cgContext.setLineWidth(0.5)
                        ctx.cgContext.move(to: CGPoint(x: margin, y: y - 3))
                        ctx.cgContext.addLine(to: CGPoint(x: pageW - margin, y: y - 3))
                        ctx.cgContext.strokePath()
                    }
                }

                // Grand total.
                y += 10
                ensureRoom(50)
                ctx.cgContext.setStrokeColor(UIColor(white: 0, alpha: 0.3).cgColor)
                ctx.cgContext.setLineWidth(1)
                ctx.cgContext.move(to: CGPoint(x: margin, y: y))
                ctx.cgContext.addLine(to: CGPoint(x: pageW - margin, y: y))
                ctx.cgContext.strokePath()
                y += 8
                let totalsLineY = y
                drawText(String(format: String(localized: "inv_report_items"), items.count),
                         font: .systemFont(ofSize: 11), color: .darkGray, gap: 4)
                let grand = items.reduce(0) { $0 + $1.purchasePrice }
                if grand > 0 {
                    let afterCount = y
                    y = totalsLineY
                    drawText("\(String(localized: "inv_report_grand_total")): \(money(grand))",
                             font: .boldSystemFont(ofSize: 13), align: .right, gap: 0)
                    y = max(y, afterCount)
                }
            }
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Batch QR labels

    /// One A4 grid (3 × 4 per page) of the items' QR codes with the item name
    /// underneath. Each tile is the existing `QRCodeImage` — identical content
    /// and look to the per-item share/print code.
    static func makeQRLabelsPDF(items: [InventoryItem]) -> Data? {
        guard !items.isEmpty else { return nil }
        let cols = 3, rows = 4
        let gridMargin: CGFloat = 40
        let cellW = (pageW - gridMargin * 2) / CGFloat(cols)
        let cellH = (pageH - gridMargin * 2) / CGFloat(rows)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageW, height: pageH))

        let data = renderer.pdfData { ctx in
            for (index, item) in items.enumerated() {
                let slot = index % (cols * rows)
                if slot == 0 { ctx.beginPage() }
                let col = slot % cols
                let row = slot / cols
                let cell = CGRect(x: gridMargin + CGFloat(col) * cellW,
                                  y: gridMargin + CGFloat(row) * cellH,
                                  width: cellW, height: cellH)

                if let qr = renderQRTile(for: item) {
                    let side = min(cellW - 24, cellH - 52)
                    let qrRect = CGRect(x: cell.midX - side / 2, y: cell.minY + 8,
                                        width: side, height: side)
                    qr.draw(in: aspectFit(qr.size, in: qrRect))
                }

                let para = NSMutableParagraphStyle()
                para.alignment = .center
                para.lineBreakMode = .byTruncatingTail
                let attr: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 9, weight: .medium),
                    .foregroundColor: UIColor.black,
                    .paragraphStyle: para]
                (item.name as NSString).draw(
                    in: CGRect(x: cell.minX + 6, y: cell.maxY - 34, width: cellW - 12, height: 26),
                    withAttributes: attr)
            }
        }
        return data
    }

    // MARK: - Helpers

    private struct CategoryGroup {
        let category: String
        let items: [InventoryItem]
        var subtotal: Double { items.reduce(0) { $0 + $1.purchasePrice } }
    }

    /// Canonical category order first, unknown categories after, items A→Z
    /// inside each group.
    private static func groupedByCategory(_ items: [InventoryItem]) -> [CategoryGroup] {
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

    /// The same QR view the per-item sheet renders for share/print, rasterised
    /// for PDF drawing.
    private static func renderQRTile(for item: InventoryItem) -> UIImage? {
        let renderer = ImageRenderer(content: QRCodeImage(content: item.qrContent, size: 140))
        renderer.scale = 3.0
        return renderer.uiImage
    }

    private static func aspectFit(_ size: CGSize, in rect: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let scale = min(rect.width / size.width, rect.height / size.height)
        let w = size.width * scale, h = size.height * scale
        return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }

    private static func drawThumbnail(_ image: UIImage, in rect: CGRect, cg: CGContext) {
        cg.saveGState()
        UIBezierPath(roundedRect: rect, cornerRadius: 5).addClip()
        // Aspect-fill inside the clip.
        let scale = max(rect.width / max(image.size.width, 1),
                        rect.height / max(image.size.height, 1))
        let w = image.size.width * scale, h = image.size.height * scale
        image.draw(in: CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h))
        cg.restoreGState()
    }

    private static func oneLine(_ s: String) -> String {
        s.replacingOccurrences(of: "\n", with: " ")
    }
}
