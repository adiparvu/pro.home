import SwiftUI

struct MortgageView: View {
    @AppStorage("prvio.mortgage.loanAmount")   private var loanAmount: Double   = 0
    @AppStorage("prvio.mortgage.interestRate") private var interestRate: Double  = 0
    @AppStorage("prvio.mortgage.termYears")    private var termYears: Double     = 25
    @AppStorage("prvio.mortgage.startDate")    private var startDateStr: String  = ""
    @AppStorage("prvio.mortgage.propertyValue") private var propertyValue: Double = 0

    @State private var isEditing = false

    private var monthlyRate: Double { interestRate / 100 / 12 }
    private var totalPayments: Int { Int(termYears) * 12 }

    private var monthlyPayment: Double {
        guard loanAmount > 0, interestRate > 0 else { return 0 }
        let r = monthlyRate
        let n = Double(totalPayments)
        return loanAmount * (r * pow(1 + r, n)) / (pow(1 + r, n) - 1)
    }

    private var paidMonths: Int {
        guard !startDateStr.isEmpty,
              let start = ISO8601DateFormatter().date(from: startDateStr) else { return 0 }
        return max(0, Calendar.current.dateComponents([.month], from: start, to: Date()).month ?? 0)
    }

    private var remainingMonths: Int { max(0, totalPayments - paidMonths) }
    private var paidAmount: Double { monthlyPayment * Double(paidMonths) }
    private var remainingAmount: Double { monthlyPayment * Double(remainingMonths) }
    private var totalInterest: Double { max(0, monthlyPayment * Double(totalPayments) - loanAmount) }
    private var paidProgress: Double { totalPayments > 0 ? Double(paidMonths) / Double(totalPayments) : 0 }

    private var equityPercent: Double {
        guard propertyValue > 0 else { return 0 }
        let equity = propertyValue - remainingLoanBalance
        return max(0, min(equity / propertyValue, 1))
    }

    private var remainingLoanBalance: Double {
        guard loanAmount > 0, interestRate > 0, paidMonths > 0 else { return loanAmount }
        let r = monthlyRate
        let n = Double(totalPayments)
        let p = Double(paidMonths)
        return loanAmount * (pow(1 + r, n) - pow(1 + r, p)) / (pow(1 + r, n) - 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Mortgage", trailing: AnyView(
                Button(loanAmount == 0 ? "Setup" : "Edit") {
                    isEditing = true
                    HapticFeedback.impact(.light)
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.blue)
            ))
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    if loanAmount == 0 {
                        setupPrompt
                    } else {
                        paymentCard
                        progressCard
                        if propertyValue > 0 { equityCard }
                        breakdownCard
                    }
                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isEditing) {
            MortgageSetupSheet(
                loanAmount: $loanAmount,
                interestRate: $interestRate,
                termYears: $termYears,
                startDateStr: $startDateStr,
                propertyValue: $propertyValue
            )
        }
    }

    // MARK: - Setup prompt

    private var setupPrompt: some View {
        GlassCard {
            VStack(spacing: 16) {
                Image(systemName: "house.and.flag.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.blue.opacity(0.7))
                Text("Mortgage Tracker")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.primary)
                Text("Enter your mortgage details to track payments, remaining balance, and equity buildup.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.primary.opacity(0.5))
                    .multilineTextAlignment(.center)
                Button { isEditing = true } label: {
                    Text("Set Up Mortgage")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.blue, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Payment card

    private var paymentCard: some View {
        GlassCard {
            VStack(spacing: 14) {
                HStack {
                    Text("Monthly Payment")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(Int(interestRate * 10) / 10)% · \(Int(termYears))yr")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.primary.opacity(0.4))
                }
                Text("€\(String(format: "%.0f", monthlyPayment))")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.primary)

                HStack(spacing: 0) {
                    MortgageStat(label: "Principal", value: "€\(Int(loanAmount))")
                    Rectangle().fill(Color.primary.opacity(0.07)).frame(width: 0.5, height: 34)
                    MortgageStat(label: "Total Interest", value: "€\(Int(totalInterest))")
                    Rectangle().fill(Color.primary.opacity(0.07)).frame(width: 0.5, height: 34)
                    MortgageStat(label: "Total Cost", value: "€\(Int(loanAmount + totalInterest))")
                }
            }
        }
    }

    // MARK: - Progress card

    private var progressCard: some View {
        GlassCard {
            VStack(spacing: 14) {
                HStack {
                    Text("Repayment Progress")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(String(format: "%.1f%%", paidProgress * 100))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.07)).frame(height: 10)
                        Capsule()
                            .fill(LinearGradient(colors: [.blue, Color(red: 0.3, green: 0.85, blue: 0.5)],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * paidProgress, height: 10)
                            .animation(.spring(response: 0.6), value: paidProgress)
                    }
                }
                .frame(height: 10)

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Paid")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.primary.opacity(0.4))
                        Text("\(paidMonths) months")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("Remaining")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.primary.opacity(0.4))
                        Text("\(remainingMonths) months")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Balance Remaining")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.primary.opacity(0.4))
                        Text("€\(Int(remainingLoanBalance))")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    if !startDateStr.isEmpty,
                       let start = ISO8601DateFormatter().date(from: startDateStr),
                       let endDate = Calendar.current.date(byAdding: .month, value: totalPayments, to: start) {
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("Free By")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.primary.opacity(0.4))
                            let f: DateFormatter = { let d = DateFormatter(); d.dateFormat = "MMM yyyy"; return d }()
                            Text(f.string(from: endDate))
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color(red: 0.3, green: 0.85, blue: 0.5))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Equity card

    private var equityCard: some View {
        GlassCard {
            VStack(spacing: 14) {
                HStack {
                    Text("Equity")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(String(format: "%.1f%%", equityPercent * 100))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(red: 0.3, green: 0.85, blue: 0.5))
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.07)).frame(height: 10)
                        Capsule()
                            .fill(Color(red: 0.3, green: 0.85, blue: 0.5))
                            .frame(width: geo.size.width * equityPercent, height: 10)
                            .animation(.spring(response: 0.6), value: equityPercent)
                    }
                }
                .frame(height: 10)

                HStack {
                    MortgageStat(label: "Property Value", value: "€\(Int(propertyValue))")
                    Rectangle().fill(Color.primary.opacity(0.07)).frame(width: 0.5, height: 34)
                    MortgageStat(label: "Your Equity", value: "€\(Int(max(0, propertyValue - remainingLoanBalance)))")
                    Rectangle().fill(Color.primary.opacity(0.07)).frame(width: 0.5, height: 34)
                    MortgageStat(label: "Owed", value: "€\(Int(remainingLoanBalance))")
                }
            }
        }
    }

    // MARK: - Breakdown card

    private var breakdownCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Payment Breakdown")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)

                let principalShare = loanAmount / (loanAmount + totalInterest)
                let interestShare  = 1 - principalShare

                VStack(spacing: 8) {
                    BreakdownRow(label: "Principal repayment", percent: principalShare, color: .blue)
                    BreakdownRow(label: "Interest charges",   percent: interestShare, color: .orange)
                }
            }
        }
    }
}

// MARK: - Sub-views

private struct MortgageStat: View {
    let label: String
    let value: String
    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color.primary.opacity(0.4))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct BreakdownRow: View {
    let label: String
    let percent: Double
    let color: Color
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                HStack(spacing: 6) {
                    Circle().fill(color).frame(width: 7, height: 7)
                    Text(label).font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.7))
                }
                Spacer()
                Text(String(format: "%.1f%%", percent * 100))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.07)).frame(height: 6)
                    Capsule().fill(color.opacity(0.7)).frame(width: geo.size.width * percent, height: 6)
                }
            }.frame(height: 6)
        }
    }
}

// MARK: - Setup sheet

struct MortgageSetupSheet: View {
    @Binding var loanAmount: Double
    @Binding var interestRate: Double
    @Binding var termYears: Double
    @Binding var startDateStr: String
    @Binding var propertyValue: Double
    @Environment(\.dismiss) private var dismiss

    @State private var loanStr = ""
    @State private var rateStr = ""
    @State private var termStr = ""
    @State private var startDate = Date()
    @State private var valueStr = ""

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        fieldCard("Loan Amount", symbol: "€", text: $loanStr, keyboard: .decimalPad)
                        fieldCard("Interest Rate (%)", symbol: "%", text: $rateStr, keyboard: .decimalPad)
                        fieldCard("Term (years)", symbol: "yr", text: $termStr, keyboard: .numberPad)
                        fieldCard("Property Value (optional)", symbol: "€", text: $valueStr, keyboard: .decimalPad)

                        GlassCard {
                            DatePicker("Mortgage Start Date", selection: $startDate, displayedComponents: .date)
                                .foregroundStyle(.primary)
                                .tint(.blue)
                        }

                        Spacer(minLength: 60)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Mortgage Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.primary.opacity(0.7))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.blue)
                }
            }
        }
        .onAppear {
            loanStr  = loanAmount > 0 ? String(Int(loanAmount)) : ""
            rateStr  = interestRate > 0 ? String(interestRate) : ""
            termStr  = termYears > 0 ? String(Int(termYears)) : "25"
            valueStr = propertyValue > 0 ? String(Int(propertyValue)) : ""
            if let d = ISO8601DateFormatter().date(from: startDateStr) { startDate = d }
        }
    }

    private func fieldCard(_ label: String, symbol: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        GlassCard {
            HStack {
                Text(label)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.primary.opacity(0.6))
                Spacer()
                HStack(spacing: 4) {
                    TextField("0", text: text)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .tint(.blue)
                        .keyboardType(keyboard)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                    Text(symbol)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.primary.opacity(0.4))
                }
            }
        }
    }

    private func save() {
        loanAmount   = Double(loanStr.replacingOccurrences(of: ",", with: ".")) ?? loanAmount
        interestRate = Double(rateStr.replacingOccurrences(of: ",", with: ".")) ?? interestRate
        termYears    = Double(termStr) ?? termYears
        propertyValue = Double(valueStr.replacingOccurrences(of: ",", with: ".")) ?? 0
        startDateStr = ISO8601DateFormatter().string(from: startDate)
        HapticFeedback.success()
        dismiss()
    }
}
