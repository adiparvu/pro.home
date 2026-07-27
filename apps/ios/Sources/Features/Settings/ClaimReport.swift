import SwiftUI
import UIKit

// MARK: - Claim report PDF ("Dosarul daunei")
//
// The document you send the insurer: the property's identity, the incident's
// facts (date, policy, amounts), the written description, and every evidence
// photo as an annex. Same rendering school as InsuranceDossier — A4,
// UIGraphicsPDFRenderer, manual page breaks, and the honesty law: a line
// renders only when the data exists. Photos are fetched (signed) BEFORE the
// synchronous render closure.

@MainActor
enum ClaimReport {

    private static let pageW: CGFloat = 595
    private static let pageH: CGFloat = 842
    private static let margin: CGFloat = 44

    /// Builds the report and returns its temp-file URL.
    static func makePDF(claim: InsuranceClaim, property: PropertyModel?) async -> URL? {
        // Pre-fetch the evidence — sync drawing needs the bits in hand.
        var photos: [UIImage] = []
        for urlString in claim.photoUrls {
            guard let url = await SignedStorage.resolve(urlString),
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let img = UIImage(data: data) else { continue }
            photos.append(img)
        }
        return render(claim: claim, property: property, photos: photos)
    }

    private static func render(claim: InsuranceClaim, property: PropertyModel?,
                               photos: [UIImage]) -> URL? {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageW, height: pageH))
        let safeName = claim.title
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName.isEmpty ? "claim" : safeName).pdf")
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
                              gap: CGFloat = 6) {
                    let attr: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                    let bounding = (s as NSString).boundingRect(
                        with: CGSize(width: contentW, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin], attributes: attr, context: nil)
                    ensureRoom(bounding.height + gap)
                    (s as NSString).draw(in: CGRect(x: margin, y: y, width: contentW,
                                                    height: bounding.height + 2),
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

                func fact(_ label: String, _ value: String?) {
                    guard let value, !value.isEmpty else { return }
                    drawText("\(label): \(value)", font: .systemFont(ofSize: 11),
                             color: .darkGray, gap: 4)
                }

                // ---- Header ----
                drawText(String(localized: "claim_report_title"),
                         font: .boldSystemFont(ofSize: 22), gap: 4)
                drawText(claim.title, font: .boldSystemFont(ofSize: 15), gap: 4)
                drawText(String(format: String(localized: "inv_report_generated"),
                                Date().formatted(date: .long, time: .omitted)),
                         font: .systemFont(ofSize: 10), color: .gray, gap: 12)

                // ---- Property identity ----
                if let p = property {
                    sectionHeader(String(localized: "inv_dossier_property"))
                    drawText(p.name, font: .boldSystemFont(ofSize: 13), gap: 4)
                    let address = [p.addressLine1, p.city, p.postalCode ?? "", p.country]
                        .filter { !$0.isEmpty }.joined(separator: ", ")
                    if !address.isEmpty {
                        drawText(address, font: .systemFont(ofSize: 11), color: .darkGray, gap: 4)
                    }
                }

                // ---- Claim facts ----
                sectionHeader(String(localized: "claim_report_facts"))
                if let d = claim.date {
                    fact(String(localized: "claim_incident_date"),
                         d.formatted(date: .long, time: .omitted))
                }
                fact(String(localized: "claim_insurer"), claim.insurer)
                fact(String(localized: "claim_policy_number"), claim.policyNumber)
                fact(String(localized: "claim_status"),
                     String(localized: String.LocalizationValue(statusKey(claim.statusKind))))
                if let amount = claim.claimedAmount {
                    fact(String(localized: "claim_claimed_amount"),
                         CurrencyService.money(amount, code: claim.currency))
                }
                if let amount = claim.approvedAmount {
                    fact(String(localized: "claim_approved_amount"),
                         CurrencyService.money(amount, code: claim.currency))
                }

                // ---- Description ----
                if let description = claim.description, !description.isEmpty {
                    sectionHeader(String(localized: "claim_report_description"))
                    drawText(description, font: .systemFont(ofSize: 11), gap: 6)
                }
                if let notes = claim.notes, !notes.isEmpty {
                    drawText(notes, font: .systemFont(ofSize: 10), color: .gray, gap: 6)
                }

                // ---- Annex: evidence photos ----
                if !photos.isEmpty {
                    sectionHeader(String(localized: "claim_report_photos"))
                    for (index, image) in photos.enumerated() {
                        let ratio = image.size.height / max(image.size.width, 1)
                        let maxH: CGFloat = 340
                        let w = min(contentW, maxH / max(ratio, 0.001))
                        let h = w * ratio
                        ensureRoom(h + 30)
                        let caption = String(format: String(localized: "claim_photo_fmt"), index + 1)
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
                }
            }
            return url
        } catch {
            return nil
        }
    }

    private static func statusKey(_ status: ClaimStatus) -> String {
        switch status {
        case .draft:     return "claim_status_draft"
        case .submitted: return "claim_status_submitted"
        case .inReview:  return "claim_status_in_review"
        case .resolved:  return "claim_status_resolved"
        }
    }
}
