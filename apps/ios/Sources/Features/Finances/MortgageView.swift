import SwiftUI

struct MortgageView: View {
    @AppStorage("prvio.mortgage.loanAmount")   var loanAmount: Double   = 0
    @AppStorage("prvio.mortgage.interestRate") var interestRate: Double  = 0
    @AppStorage("prvio.mortgage.termYears")    var termYears: Double     = 25
    @AppStorage("prvio.mortgage.startDate")    var startDateStr: String  = ""
    @AppStorage("prvio.mortgage.propertyValue") var propertyValue: Double = 0

    @State var isEditing = false

    var monthlyRate: Double { interestRate / 100 / 12 }
    var totalPayments: Int { Int(termYears) * 12 }

    var monthlyPayment: Double {
        guard loanAmount > 0, interestRate > 0 else { return 0 }
        let r = monthlyRate
        let n = Double(totalPayments)
        return loanAmount * (r * pow(1 + r, n)) / (pow(1 + r, n) - 1)
    }

    var paidMonths: Int {
        guard !startDateStr.isEmpty,
              let start = ISO8601DateFormatter().date(from: startDateStr) else { return 0 }
        return max(0, Calendar.current.dateComponents([.month], from: start, to: Date()).month ?? 0)
    }

    var remainingMonths: Int { max(0, totalPayments - paidMonths) }
    var paidAmount: Double { monthlyPayment * Double(paidMonths) }
    var remainingAmount: Double { monthlyPayment * Double(remainingMonths) }
    var totalInterest: Double { max(0, monthlyPayment * Double(totalPayments) - loanAmount) }
    var paidProgress: Double { totalPayments > 0 ? Double(paidMonths) / Double(totalPayments) : 0 }

    var equityPercent: Double {
        guard propertyValue > 0 else { return 0 }
        let equity = propertyValue - remainingLoanBalance
        return max(0, min(equity / propertyValue, 1))
    }

    var remainingLoanBalance: Double {
        guard loanAmount > 0, interestRate > 0, paidMonths > 0 else { return loanAmount }
        let r = monthlyRate
        let n = Double(totalPayments)
        let p = Double(paidMonths)
        return loanAmount * (pow(1 + r, n) - pow(1 + r, p)) / (pow(1 + r, n) - 1)
    }

    var body: some View {
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
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Mortgage")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(loanAmount == 0 ? String(localized: "Setup") : String(localized: "Edit")) {
                    isEditing = true
                    HapticFeedback.impact(.light)
                }
                .font(AppFont.body)
                .foregroundStyle(Color.accentColor)
            }
        }
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
}
