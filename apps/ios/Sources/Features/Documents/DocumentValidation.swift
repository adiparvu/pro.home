import Foundation
import SwiftUI

// MARK: - Document validation sweeps (Document Intelligence D6)
//
// Pure, synchronous rules over the loaded working set that surface documents
// needing attention, grouped into a review inbox with one-tap fixes:
//
//   • duplicates  — two or more documents that share a real identifier
//                   (policy / contract / doc number / series / barcode /
//                   fiscal / client code), or the same issuer + document
//                   number. The fix: open both and delete the extra.
//   • expired     — expiry date already in the past. The fix: open the editor
//                   to renew (update expiry / renewal date).
//   • incomplete  — a category-required field (DocumentCategorySchema) is
//                   missing. The fix: open the editor to fill it in.
//
// Everything is derived, never stored — the sweep re-runs on the live data, so
// fixing a document removes its issue automatically. Dismissals are per-device.

enum DocValidationKind: String {
    case duplicate, expired, incomplete

    var icon: String {
        switch self {
        case .duplicate:  return "doc.on.doc.fill"
        case .expired:    return "calendar.badge.exclamationmark"
        case .incomplete: return "exclamationmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .duplicate:  return .orange
        case .expired:    return .red
        case .incomplete: return .blue
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .duplicate:  return "doc_val_duplicate"
        case .expired:    return "doc_val_expired"
        case .incomplete: return "doc_val_incomplete"
        }
    }
}

/// One actionable finding in the review inbox.
struct DocValidationIssue: Identifiable {
    let id: String
    let kind: DocValidationKind
    let primary: DocumentModel
    /// For `.duplicate`: the full cluster (primary + the others sharing a key).
    var cluster: [DocumentModel] = []
    /// For `.incomplete`: the category-required fields still empty.
    var missing: [DocField] = []
    /// For `.duplicate`: the identifier value that collided (for the subtitle).
    var sharedKey: String?
}

enum DocumentValidation {

    /// Runs all three sweeps and returns their combined, de-duplicated findings.
    static func sweep(_ docs: [DocumentModel], today: Date = Date()) -> [DocValidationIssue] {
        duplicates(docs) + expired(docs, today: today) + incomplete(docs)
    }

    // MARK: Duplicates

    private static func duplicates(_ docs: [DocumentModel]) -> [DocValidationIssue] {
        // Map each normalized identifier value → the docs carrying it.
        var byKey: [String: [DocumentModel]] = [:]
        for doc in docs {
            for key in identifierKeys(doc) {
                byKey[key, default: []].append(doc)
            }
        }
        var issues: [DocValidationIssue] = []
        var seenClusters: Set<String> = []
        for (key, group) in byKey where group.count >= 2 {
            let ids = group.map(\.id.uuidString).sorted()
            let clusterId = "dup:" + ids.joined(separator: ",")
            guard seenClusters.insert(clusterId).inserted else { continue }
            issues.append(DocValidationIssue(
                id: clusterId, kind: .duplicate, primary: group[0],
                cluster: group, sharedKey: displayKey(key)))
        }
        return issues.sorted { $0.primary.name < $1.primary.name }
    }

    /// The identifier "fingerprints" a document can collide on: each real,
    /// long-enough identifier value, plus an issuer+number composite.
    private static func identifierKeys(_ d: DocumentModel) -> Set<String> {
        var keys: Set<String> = []
        func add(_ label: String, _ raw: String?) {
            guard let norm = normalize(raw), norm.count >= 4 else { return }
            keys.insert("\(label):\(norm)")
        }
        add("policy", d.policyNumber)
        add("contract", d.contractCode)
        add("number", d.docNumber)
        add("series", d.series)
        add("barcode", d.barcode)
        add("fiscal", d.fiscalCode)
        add("client", d.clientCode)
        // Issuer + document number together (weaker signal, still a real dupe).
        if let issuer = normalize(d.issuerCompany), let num = normalize(d.docNumber),
           issuer.count >= 3, num.count >= 2 {
            keys.insert("issuernum:\(issuer)|\(num)")
        }
        return keys
    }

    private static func normalize(_ s: String?) -> String? {
        guard let s else { return nil }
        let cleaned = s.uppercased().filter { $0.isLetter || $0.isNumber }
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func displayKey(_ key: String) -> String {
        // "policy:AB123" → "AB123"; "issuernum:ENGIE|55" → "ENGIE·55".
        guard let sep = key.firstIndex(of: ":") else { return key }
        let value = String(key[key.index(after: sep)...])
        return value.replacingOccurrences(of: "|", with: "·")
    }

    // MARK: Expired

    private static func expired(_ docs: [DocumentModel], today: Date) -> [DocValidationIssue] {
        let startOfToday = Calendar.current.startOfDay(for: today)
        return docs.compactMap { doc in
            guard let iso = doc.expiresAt, let day = AppDate.day(from: iso), day < startOfToday
            else { return nil }
            return DocValidationIssue(id: "exp:\(doc.id.uuidString):\(iso)",
                                      kind: .expired, primary: doc)
        }
        .sorted { ($0.primary.expiresAt ?? "") < ($1.primary.expiresAt ?? "") }
    }

    // MARK: Incomplete

    private static func incomplete(_ docs: [DocumentModel]) -> [DocValidationIssue] {
        docs.compactMap { doc in
            let missing = DocumentCategorySchema.requiredFields(for: doc.category)
                .filter { !hasValue(doc, $0) }
            guard !missing.isEmpty else { return nil }
            let sig = missing.map(\.rawValue).joined(separator: ",")
            return DocValidationIssue(id: "inc:\(doc.id.uuidString):\(sig)",
                                      kind: .incomplete, primary: doc, missing: missing)
        }
        .sorted { $0.primary.name < $1.primary.name }
    }

    /// Whether a document has a non-empty value for a schema field.
    static func hasValue(_ d: DocumentModel, _ field: DocField) -> Bool {
        func nonEmpty(_ s: String?) -> Bool { !(s ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
        switch field {
        case .subcategory:   return nonEmpty(d.subcategory)
        case .description:   return nonEmpty(d.description)
        case .tags:          return !d.tags.isEmpty
        case .priority:      return nonEmpty(d.priority)
        case .issuedAt:      return nonEmpty(d.issuedAt)
        case .expiresAt:     return nonEmpty(d.expiresAt)
        case .renewAt:       return nonEmpty(d.renewAt)
        case .notifyAt:      return nonEmpty(d.notifyAt)
        case .issuerCompany: return nonEmpty(d.issuerCompany)
        case .issuerContact: return nonEmpty(d.issuerContact)
        case .issuerPhone:   return nonEmpty(d.issuerPhone)
        case .issuerEmail:   return nonEmpty(d.issuerEmail)
        case .issuerWebsite: return nonEmpty(d.issuerWebsite)
        case .clientNumber:  return nonEmpty(d.clientNumber)
        case .docNumber:     return nonEmpty(d.docNumber)
        case .series:        return nonEmpty(d.series)
        case .contractCode:  return nonEmpty(d.contractCode)
        case .clientCode:    return nonEmpty(d.clientCode)
        case .fiscalCode:    return nonEmpty(d.fiscalCode)
        case .policyNumber:  return nonEmpty(d.policyNumber)
        case .barcode:       return nonEmpty(d.barcode)
        case .value:         return d.value != nil
        case .currency:      return nonEmpty(d.currency)
        case .vat:           return d.vat != nil
        case .recurrence:    return nonEmpty(d.recurrence)
        }
    }
}

// MARK: - Per-device dismissals
//
// Dismissing an issue is a personal "I've seen this" — like favorites, it lives
// in UserDefaults, not the shared row. Issue ids embed a content signature
// (date / missing-field set), so a dismissed issue re-surfaces if the
// underlying problem changes but not while it stays exactly the same.

enum DocReviewDismissStore {
    private static let key = "prvio.document.review.dismissed"

    static func ids() -> Set<String> { Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }
    static func isDismissed(_ id: String) -> Bool { ids().contains(id) }

    static func dismiss(_ id: String) {
        var s = ids(); s.insert(id)
        UserDefaults.standard.set(Array(s), forKey: key)
    }

    /// Prune dismissals whose issue no longer exists, so the set can't grow
    /// unbounded as documents change or are deleted.
    static func prune(keeping live: Set<String>) {
        let pruned = ids().intersection(live)
        UserDefaults.standard.set(Array(pruned), forKey: key)
    }
}
