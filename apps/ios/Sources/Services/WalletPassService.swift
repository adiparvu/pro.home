import Foundation
import PassKit
import UIKit

@MainActor
final class WalletPassService: ObservableObject {
    static let shared = WalletPassService()

    @Published var canAddPasses: Bool = false

    private init() {
        canAddPasses = PKPassLibrary.isPassLibraryAvailable()
    }

    // MARK: - Check if a pass is already added

    func isAdded(passTypeIdentifier: String, serialNumber: String) -> Bool {
        guard PKPassLibrary.isPassLibraryAvailable() else { return false }
        let library = PKPassLibrary()
        return library.passes().contains {
            $0.passTypeIdentifier == passTypeIdentifier && $0.serialNumber == serialNumber
        }
    }

    // MARK: - Add a .pkpass file from the app bundle or a URL

    func addPass(from url: URL, in viewController: UIViewController) {
        guard let data = try? Data(contentsOf: url),
              let pass = try? PKPass(data: data) else { return }
        let vc = PKAddPassesViewController(pass: pass)
        if let vc { viewController.present(vc, animated: true) }
    }

    // MARK: - Present pass add UI for a pre-created PKPass (requires server-side signing)

    func presentAddUI(for passData: Data, in viewController: UIViewController) throws {
        let pass = try PKPass(data: passData)
        guard let vc = PKAddPassesViewController(pass: pass) else { return }
        viewController.present(vc, animated: true)
    }

    // MARK: - Open a specific pass in Wallet

    func openPass(passTypeIdentifier: String, serialNumber: String) {
        guard PKPassLibrary.isPassLibraryAvailable() else { return }
        let library = PKPassLibrary()
        if let pass = library.passes().first(where: {
            $0.passTypeIdentifier == passTypeIdentifier && $0.serialNumber == serialNumber
        }) {
            library.openPaymentSetup()
            _ = pass
        }
    }

    // MARK: - Contractor / Guest pass metadata builder
    // Returns a JSON dict that your server signs into a .pkpass

    func contractorPassPayload(
        name: String,
        role: String,
        propertyAddress: String,
        validFrom: Date,
        validUntil: Date,
        accessCode: String
    ) -> [String: Any] {
        let df = ISO8601DateFormatter()
        return [
            "formatVersion": 1,
            "passTypeIdentifier": "pass.com.prvio.app.contractor",
            "serialNumber": UUID().uuidString,
            "teamIdentifier": "SU92TVZT8W",
            "organizationName": "PRVIO",
            "description": "Acces contractor",
            "foregroundColor": "rgb(255,255,255)",
            "backgroundColor": "rgb(30,50,90)",
            "generic": [
                "primaryFields": [
                    ["key": "name", "label": "Contractor", "value": name]
                ],
                "secondaryFields": [
                    ["key": "role", "label": "Rol", "value": role],
                    ["key": "address", "label": "Proprietate", "value": propertyAddress]
                ],
                "auxiliaryFields": [
                    ["key": "valid", "label": "Valabil", "value": "\(df.string(from: validFrom)) – \(df.string(from: validUntil))"],
                    ["key": "code", "label": "Cod acces", "value": accessCode]
                ]
            ],
            "expirationDate": df.string(from: validUntil)
        ]
    }
}
