import Flutter
import UIKit
import FirebaseAppCheck
import FirebaseCore
import FirebaseMessaging
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  // Garde une référence vivante du browser Bonjour sinon il est désalloué
  // immédiatement et iOS ne déclenche pas le dialog "Réseau local".
  private var localNetworkBrowser: NetServiceBrowser?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // App Check provider factory MUST be installed BEFORE FirebaseApp.configure()
    // for Firebase to use it during internal init. In debug builds we wire the
    // debug provider so the simulator (no DeviceCheck hardware) gets a token
    // from the FIRAAppCheckDebugToken env var configured in Runner.xcscheme.
    #if DEBUG
    AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
    #else
    // Release: DeviceCheckProviderFactory handles App Attest on iOS 14+ and
    // falls back to DeviceCheck on older devices.
    AppCheck.setAppCheckProviderFactory(DeviceCheckProviderFactory())
    #endif

    // Firebase init AVANT GeneratedPluginRegistrant (sinon cloud_functions crash).
    FirebaseApp.configure()

    // UNUserNotificationCenter — requis pour recevoir les notifications en
    // foreground (onMessage côté Flutter) et pour afficher les alertes.
    UNUserNotificationCenter.current().delegate = self

    // Messaging delegate — relaie le token APNs vers FCM via didReceiveRegistrationToken.
    Messaging.messaging().delegate = self

    // Force iOS à demander la permission "Réseau local" en lançant un browse
    // Bonjour. Indispensable pour atteindre Firebase emulator sur le LAN.
    triggerLocalNetworkPermission()

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: — APNs device token → FCM

  /// iOS appelle cette méthode quand l'app reçoit son token APNs.
  /// On le passe immédiatement à FCM pour qu'il génère un FCM token.
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
    super.application(
      application,
      didRegisterForRemoteNotificationsWithDeviceToken: deviceToken
    )
  }

  // MARK: — UNUserNotificationCenterDelegate

  /// Appelée quand une notification arrive en foreground.
  /// Retourne .banner + .sound pour que la notif soit visible même app ouverte.
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler:
      @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound, .badge])
  }

  /// Appelée quand l'utilisateur tape sur une notification.
  /// Le plugin firebase_messaging intercepte cet event — ne pas l'overrider
  /// sans appeler super car cela briserait onMessageOpenedApp côté Dart.
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    super.userNotificationCenter(
      center,
      didReceive: response,
      withCompletionHandler: completionHandler
    )
  }

  // MARK: — Local network permission (dev emulator)

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

// MARK: — MessagingDelegate

/// Extension MessagingDelegate séparée pour la clarté.
/// didReceiveRegistrationToken est appelée :
/// - Au démarrage (token initial).
/// - Quand FCM rafraîchit le token (rotation automatique).
///
/// Le plugin firebase_messaging intercepte déjà cet event côté Dart via
/// onTokenRefresh — cette extension est une sécurité supplémentaire pour
/// les cas où le plugin Dart n'est pas encore prêt.
extension AppDelegate: MessagingDelegate {
  func messaging(
    _ messaging: Messaging,
    didReceiveRegistrationToken fcmToken: String?
  ) {
    guard let fcmToken else { return }
    // Log uniquement en debug pour ne pas exposer le token dans les logs prod.
    #if DEBUG
    print("[FCM] Token reçu: \(fcmToken)")
    #endif
    // Le plugin firebase_messaging Flutter intercepte ce token via son propre
    // MessagingDelegate interne. Pas besoin de le transmettre manuellement.
  }
}
