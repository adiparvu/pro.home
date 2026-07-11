import SwiftUI

// MARK: - Rent roll (lease cashflow, derived at read time)
//
// A cashflow snapshot over a property's leases. EVERYTHING here is derived
// from real contract data — projected monthly income (each lease converted to
// the owner's preferred currency via live FX, so mixed-currency portfolios sum
// honestly), the next rent due date (from each lease's payment day), deposits
// held and occupancy. There is no payment ledger yet, so the rent roll never
// claims "paid" or "overdue" — it states only what the contracts themselves
// say, in line with the app's honesty rule.

struct RentRoll {

    /// One upcoming rent charge — the soonest occurrence of a lease's payment
    /// day at or after today.
    struct Upcoming: Identifiable {
        let id: UUID
        let tenantName: String
        let dueDate: Date
        let amount: Double
        let currency: String
    }

    var activeLeases: Int
    /// Sum of monthly rents, each converted to `currency` (the preferred one).
    var monthlyIncome: Double
    /// Sum of deposits held, converted to `currency`.
    var depositsHeld: Double
    var occupants: Int
    var currency: String
    /// The soonest upcoming rent across every active lease, if any.
    var nextDue: Upcoming?
    /// True when leases span more than one currency — the UI shows a subtle
    /// "≈" so the converted total never reads as exact.
    var hasMixedCurrency: Bool

    var isEmpty: Bool { activeLeases == 0 || monthlyIncome <= 0 }
    var annualIncome: Double { monthlyIncome * 12 }

    /// Build the roll from the active leases. `nameFor` resolves a tenant's
    /// display name; `convert` applies the app's live FX (amount, fromCode) →
    /// preferred; `preferred` is the owner's display currency.
    static func build(
        leases: [TenantLease],
        nameFor: (UUID) -> String,
        convert: (Double, String) -> Double,
        preferred: String
    ) -> RentRoll {
        let active = leases.filter { !$0.hasEnded }
        let currencies = Set(active.compactMap { lease -> String? in
            lease.monthlyRent == nil ? nil : lease.currency
        })

        var monthly = 0.0
        var deposits = 0.0
        var occupants = 0
        var upcoming: [Upcoming] = []
        let cal = Calendar.current
        let now = Date()

        for lease in active {
            if let rent = lease.monthlyRent { monthly += convert(rent, lease.currency) }
            if let dep = lease.deposit { deposits += convert(dep, lease.currency) }
            occupants += lease.occupants ?? 0

            if let dom = lease.paymentDay, (1...31).contains(dom),
               let rent = lease.monthlyRent,
               let due = nextPaymentDate(dayOfMonth: dom, after: now, calendar: cal),
               // Don't project a charge past the lease's own end.
               lease.leaseEnd.flatMap({ AppDate.day(from: $0) }).map({ due <= $0 }) ?? true {
                upcoming.append(Upcoming(id: lease.id, tenantName: nameFor(lease.memberId),
                                         dueDate: due, amount: rent, currency: lease.currency))
            }
        }

        return RentRoll(
            activeLeases: active.filter { $0.monthlyRent != nil }.count,
            monthlyIncome: monthly,
            depositsHeld: deposits,
            occupants: occupants,
            currency: preferred,
            nextDue: upcoming.min { $0.dueDate < $1.dueDate },
            hasMixedCurrency: currencies.count > 1)
    }

    /// The next date matching `dayOfMonth` at or after `after` (rolls into next
    /// month when today is already past the day; short months clamp forward).
    private static func nextPaymentDate(dayOfMonth: Int, after: Date, calendar cal: Calendar) -> Date? {
        var comps = DateComponents()
        comps.day = dayOfMonth
        return cal.nextDate(after: cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: after)) ?? after,
                            matching: comps,
                            matchingPolicy: .nextTime,
                            direction: .forward)
    }
}

// MARK: - Rent roll card

/// The cashflow header for the Tenants screen: projected monthly income (with
/// the annual figure), the next rent due and deposits held — a landlord's
/// glance at what the property earns.
struct RentRollCard: View {
    let roll: RentRoll

    private func money(_ amount: Double) -> String {
        CurrencyService.money(amount, code: roll.currency, whole: true)
    }

    var body: some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                // Headline: monthly projected income.
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("rentroll_monthly_income")
                            .font(AppFont.scaled(11, weight: .semibold))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                            .textCase(.uppercase)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            if roll.hasMixedCurrency {
                                Text("≈").font(AppFont.scaled(18, weight: .semibold))
                                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                            }
                            Text(money(roll.monthlyIncome))
                                .font(AppFont.scaled(28, weight: .bold))
                                .foregroundStyle(.primary)
                            Text("/\(String(localized: "month"))")
                                .font(AppFont.subheadline)
                                .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                        }
                    }
                    Spacer()
                    Image(systemName: "key.fill")
                        .font(AppFont.scaled(16, weight: .semibold))
                        .foregroundStyle(Color.brandSuccess)
                        .frame(width: 40, height: 40)
                        .background(Color.brandSuccess.opacity(0.12), in: Circle())
                }

                Text(String(format: String(localized: "rentroll_per_year"), money(roll.annualIncome)))
                    .font(AppFont.scaled(12))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))

                Divider().opacity(0.4)

                // Secondary metrics.
                HStack(alignment: .top, spacing: 12) {
                    if let due = roll.nextDue {
                        metric(icon: "calendar.badge.clock", color: .orange,
                               label: "rentroll_next_rent",
                               value: AppDate.medium.string(from: due.dueDate),
                               sub: due.tenantName)
                    }
                    if roll.depositsHeld > 0 {
                        metric(icon: "lock.shield.fill", color: Color.brandSkyBlue,
                               label: "rentroll_deposits",
                               value: money(roll.depositsHeld), sub: nil)
                    }
                    if roll.occupants > 0 {
                        metric(icon: "person.2.fill", color: .purple,
                               label: "rentroll_occupants",
                               value: "\(roll.occupants)", sub: nil)
                    }
                }
            }
        }
    }

    private func metric(icon: String, color: Color, label: LocalizedStringKey,
                        value: String, sub: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(AppFont.scaled(11, weight: .semibold))
                    .foregroundStyle(color)
                Text(label)
                    .font(AppFont.scaled(10, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                    .lineLimit(1)
            }
            Text(value)
                .font(AppFont.scaled(14, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            if let sub {
                Text(sub)
                    .font(AppFont.scaled(11))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
