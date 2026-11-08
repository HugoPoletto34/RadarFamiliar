import Flutter
import GoogleMaps
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Vem de ios/Flutter/Secrets.xcconfig (fora do git). Sem chave, o app usa OpenStreetMap.
    if let key = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String, !key.isEmpty {
      GMSServices.provideAPIKey(key)
    }
    UNUserNotificationCenter.current().delegate = self
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    registerForPush()
    return launched
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // O plugin do FCM precisa estar registrado antes do pedido de token APNs.
    UNUserNotificationCenter.current().delegate = self
    registerForPush()
  }

  private func registerForPush() {
    UIApplication.shared.registerForRemoteNotifications()
  }
}
