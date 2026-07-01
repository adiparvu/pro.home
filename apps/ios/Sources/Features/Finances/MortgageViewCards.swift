import SwiftUI

// MARK: - MortgageView cards

extension MortgageView {

    var setupPrompt: some View {
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
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    .multilineTextAlignment(.center)
                Button { isEditing = true } label: {
                    Text("Set Up Mortgage")
                        .font(AppFont.footnoteEmphasis)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.blue, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    var paymentCard: some View {
        GlassCard {
            VStack(spacing: 14) {
                HStack {
                    Text("Monthly Payment")
                        .font(AppFont.subheadline)
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
                    Rectangle().fill(Color.primary.opacity(AppOpacity.subtleFill)).frame(width: 0.5, height: 34)
                    MortgageStat(label: "Total Interest", value: "€\(Int(totalInterest))")
                    Rectangle().fill(Color.primary.opacity(AppOpacity.subtleFill)).frame(width: 0.5, height: 34)
                    MortgageStat(label: "Total Cost", value: "€\(Int(loanAmount + totalInterest))")
                }
            }
        }
    }

    var progressCard: some View {
        GlassCard {
            VStack(spacing: 14) {
                HStack {
                    Text("Repayment Progress")
                        .font(AppFont.subheadline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(String(format: "%.1f%%", paidProgress * 100))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(AppOpacity.subtleFill)).frame(height: 10)
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
                            .font(AppFont.footnoteEmphasis)
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("Remaining")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.primary.opacity(0.4))
                        Text("\(remainingMonths) months")
                            .font(AppFont.footnoteEmphasis)
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

    var equityCard: some View {
        GlassCard {
            VStack(spacing: 14) {
                HStack {
                    Text("Equity")
                        .font(AppFont.subheadline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(String(format: "%.1f%%", equityPercent * 100))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(red: 0.3, green: 0.85, blue: 0.5))
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(AppOpacity.subtleFill)).frame(height: 10)
                        Capsule()
                            .fill(Color(red: 0.3, green: 0.85, blue: 0.5))
                            .frame(width: geo.size.width * equityPercent, height: 10)
                            .animation(.spring(response: 0.6), value: equityPercent)
                    }
                }
                .frame(height: 10)

                HStack {
                    MortgageStat(label: "Property Value", value: "€\(Int(propertyValue))")
                    Rectangle().fill(Color.primary.opacity(AppOpacity.subtleFill)).frame(width: 0.5, height: 34)
                    MortgageStat(label: "Your Equity", value: "€\(Int(max(0, propertyValue - remainingLoanBalance)))")
                    Rectangle().fill(Color.primary.opacity(AppOpacity.subtleFill)).frame(width: 0.5, height: 34)
                    MortgageStat(label: "Owed", value: "€\(Int(remainingLoanBalance))")
                }
            }
        }
    }

    var breakdownCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Payment Breakdown")
                    .font(AppFont.subheadline)
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

struct MortgageStat: View {
    let label: LocalizedStringKey
    let value: String
    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(AppFont.captionEmphasis)
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

struct BreakdownRow: View {
    let label: LocalizedStringKey
    let percent: Double
    let color: Color
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                HStack(spacing: 6) {
                    Circle().fill(color).frame(width: 7, height: 7)
                    Text(label).font(.system(size: 13)).foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                }
                Spacer()
                Text(String(format: "%.1f%%", percent * 100))
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(.primary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(AppOpacity.subtleFill)).frame(height: 6)
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
                                .tint(.accentColor)
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
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .font(AppFont.subheadline)
                        .foregroundStyle(Color.accentColor)
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
                        .font(AppFont.headline)
                        .foregroundStyle(.primary)
                        .tint(.accentColor)
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
