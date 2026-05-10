import Flutter
import UIKit
import FirebaseCore

@main
@objc class AppDelegate: FlutterAppDelegate {
  // Garde une référence vivante du browser Bonjour sinon il est désalloué
  // immédiatement et iOS ne déclenche pas le dialog "Réseau local".
  private var localNetworkBrowser: NetServiceBrowser?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Firebase init AVANT GeneratedPluginRegistrant (sinon cloud_functions crash).
    FirebaseApp.configure()

    // Force iOS à demander la permission "Réseau local" en lançant un browse
    // Bonjour. Une simple requête HTTP vers une IP privée ne suffit pas à
    // déclencher le dialog. Indispensable pour atteindre Firebase emulator
    // sur le LAN en mode dev.
    triggerLocalNetworkPermission()

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func triggerLocalNetworkPermission() {
    let browser = NetServiceBrowser()
    browser.searchForServices(ofType: "_http._tcp", inDomain: "local.")
    localNetworkBrowser = browser
    // Stop le browse au bout de 3s — la permission est déjà déclenchée
    // au premier searchForServices.
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
      self?.localNetworkBrowser?.stop()
      self?.localNetworkBrowser = nil
    }
  }
}
