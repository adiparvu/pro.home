import AppIntents
import Foundation

// MARK: - Log expense (Apple Pay → PRVIO)
//
// The bridge for the Shortcuts "Transaction" automation: every Apple Pay tap
// can run this intent with the merchant and amount, and the expense lands in
// the household ledger automatically — categorized by merchant, no app open.
// The intent itself only QUEUES: it runs in a cold background launch where
// network and session aren't guaranteed, so it appends to the shared outbox
// and MainTabView drains it into `financial_records` on the next foreground —
// the same offline-safe pattern the widget task-completions use.

struct LogExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Log expense"
    static var description = IntentDescription(
        "Adds an expense to PRVIO Finances. Wire it to the Shortcuts 'Transaction' automation to track Apple Pay payments automatically.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Merchant")
    var merchant: String

    @Parameter(title: "Amount")
    var amount: Double

    @Parameter(title: "Card")
    var card: String?

    @Parameter(title: "Note")
    var note: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amount) at \(\.$merchant)") {
            \.$card
            \.$note
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let name = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard amount > 0, !name.isEmpty else {
            return .result(dialog: IntentDialog(stringLiteral:
                String(localized: "intent_expense_invalid")))
        }
        SharedDataStore.appendPendingExpense(SharedDataStore.PendingExpense(
            id: UUID(),
            merchant: name,
            amount: amount,
            card: card?.isEmpty == true ? nil : card,
            note: note?.isEmpty == true ? nil : note,
            date: AppDate.dayString(from: Date())))
        return .result(dialog: IntentDialog(stringLiteral:
            String(format: String(localized: "intent_expense_logged_fmt"), name)))
    }
}

// MARK: - Merchant → category

/// Maps a card-statement merchant name onto the ledger's existing category
/// tokens (see `categoryIcons` in FinancesViewComponents). Chains cover the
/// household's markets (RO + BE); anything unknown lands in "other", which
/// the user can recategorize from the row's edit menu.
enum MerchantCategorizer {
    private static let rules: [(category: String, needles: [String])] = [
        ("groceries",  ["lidl", "kaufland", "carrefour", "mega image", "profi", "auchan",
                        "penny", "selgros", "metro", "delhaize", "colruyt", "aldi", "spar",
                        "freshful", "okay", "cora"]),
        ("transport",  ["omv", "petrom", "mol ", "lukoil", "rompetrol", "shell", "q8",
                        "esso", "total", "uber", "bolt", "cfr", "metrorex", "stb",
                        "parcare", "parking", "sncb", "de lijn", "stib", "nmbs"]),
        ("dining",     ["mcdonald", "kfc", "starbucks", "subway", "pizza", "restaurant",
                        "bistro", "cafe", "caffe", "coffee", "glovo", "tazz",
                        "takeaway", "foodpanda", "shaorma", "kebab"]),
        ("healthcare", ["catena", "helpnet", "sensiblu", "farmaci", "pharmacy",
                        "apotheek", "dr.max", "clinic", "medlife", "regina maria",
                        "sanador", "dent"]),
        ("utilities",  ["enel", "e.on", "eon ", "engie", "electrica", "hidroelectrica",
                        "digi", "orange", "vodafone", "telekom", "luminus", "proximus",
                        "base", "telenet"]),
        ("shopping",   ["emag", "altex", "flanco", "zara", "h&m", "decathlon", "ikea",
                        "jysk", "dedeman", "leroy", "hornbach", "brico", "amazon",
                        "temu", "aliexpress", "pepco", "sinsay", "action", "kiabi"]),
        ("supplies",   ["dm ", "rossmann", "kruidvat"]),
    ]

    static func category(for merchant: String) -> String {
        let m = merchant.lowercased()
        for rule in rules where rule.needles.contains(where: { m.contains($0) }) {
            return rule.category
        }
        return "other"
    }
}
