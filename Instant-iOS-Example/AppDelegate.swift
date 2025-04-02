//
//  Copyright © 2017-2025 PSPDFKit GmbH. All rights reserved.
//
//  The Nutrient Sample applications are licensed with a modified BSD license.
//  Please see License for details. This notice may not be removed from this file.
//

import UIKit
import Instant

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Set your license key here. Nutrient is commercial software.
        // Each Nutrient license is bound to a specific app bundle id.
        // Visit https://my.nutrient.io to get your demo or commercial license key.
        SDK.setLicenseKey("YOUR_LICENSE_KEY_GOES_HERE")

        let window = UIWindow()
        do {
            // The serverURL needs to be an absolute URL that the Nutrient Document Engine can be reached at.
            // If you are running the server on your local development machine use your local IP address,
            // which you can see by option-clicking the Wi-Fi icon in the macOS menu bar.
            // If you deployed the example server elsewhere, use the address and port of that container.
            let instantClient = try InstantClient(serverURL: URL(string: "http://localhost:5000/")!)

            // Client for the example server, as a stand-in for your own backend.
            // Note the example server expects an empty password.
            let apiClient = APIClient(baseURL: URL(string: "http://localhost:3000/")!, userID: "test", password: "")

            let documentsController = DocumentsViewController(instantClient: instantClient, apiClient: apiClient)
            documentsController.title = "Nutrient Instant"

            let navigationController = UINavigationController(rootViewController: documentsController)
            navigationController.navigationBar.prefersLargeTitles = true
            window.rootViewController = navigationController
        } catch
            let error as InstantError
            where error.code == .unknown
                || error.code == .databaseAccessFailed
                || error.code == .couldNotWriteToDisk {
            // A real world application can have parts that might continue to work just fine without Instant. For the
            // sake of this sample we handle the errors that can happen when creating the client by printing them.
            print("Failed setting up the client: \(error)")
        } catch {
            fatalError("Only exists to make the catch exhaustive")
        }
        window.makeKeyAndVisible()
        self.window = window

        return true
    }
}
