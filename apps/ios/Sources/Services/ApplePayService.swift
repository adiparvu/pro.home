import Foundation
import PassKit
import UIKit

@MainActor
final class ApplePayService: NSObject, ObservableObject {
    static let shared = ApplePayService()

    @Published var isAvailable: Bool = false

    private override init() {
        super.init()
        isAvailable = PKPaymentAuthorizationController.canMakePayments(
            usingNetworks: [.visa, .masterCard, .amex]
        )
    }

    static let supportedNetworks: [PKPaymentNetwork] = [.visa, .masterCard, .amex, .maestro]
    static let merchantID = "merchant.com.prvio.app"

    // MARK: - Build a payment request

    func paymentRequest(
        amount: Decimal,
        currency: String = "RON",
        label: String,
        countryCode: String = "RO"
    ) -> PKPaymentRequest {
        let request = PKPaymentRequest()
        request.merchantIdentifier = Self.merchantID
        request.supportedNetworks = Self.supportedNetworks
        request.merchantCapabilities = .threeDSecure
        request.countryCode = countryCode
        request.currencyCode = currency
        request.paymentSummaryItems = [
            PKPaymentSummaryItem(
                label: label,
                amount: NSDecimalNumber(decimal: amount)
            ),
            PKPaymentSummaryItem(
                label: "PRVIO",
                amount: NSDecimalNumber(decimal: amount)
            )
        ]
        return request
    }

    // MARK: - Present payment sheet

    func present(
        amount: Decimal,
        currency: String = "RON",
        label: String,
        in viewController: UIViewController,
        onSuccess: @escaping (PKPayment) -> Void
    ) {
        let request = paymentRequest(amount: amount, currency: currency, label: label)
        guard let vc = PKPaymentAuthorizationViewController(paymentRequest: request) else { return }
        _onSuccess = onSuccess
        _authVC = vc
        vc.delegate = self
        viewController.present(vc, animated: true)
    }

    private var _onSuccess: ((PKPayment) -> Void)?
    private weak var _authVC: PKPaymentAuthorizationViewController?
}

extension ApplePayService: PKPaymentAuthorizationViewControllerDelegate {
    nonisolated func paymentAuthorizationViewController(
        _ controller: PKPaymentAuthorizationViewController,
        didAuthorizePayment payment: PKPayment,
        handler completion: @escaping (PKPaymentAuthorizationResult) -> Void
    ) {
        completion(PKPaymentAuthorizationResult(status: .success, errors: nil))
        Task { @MainActor in
            self._onSuccess?(payment)
        }
    }

    nonisolated func paymentAuthorizationViewControllerDidFinish(_ controller: PKPaymentAuthorizationViewController) {
        // PassKit delivers this delegate callback on the main thread.
        MainActor.assumeIsolated { controller.dismiss(animated: true) }
    }
}
