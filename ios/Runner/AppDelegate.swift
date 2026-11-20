import CoreLocation
import Flutter
import GoogleMaps
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let locationShare = SharingLocationKeeper()

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
    locationShare.register(messenger: engineBridge.applicationRegistrar.messenger())
  }

  private func registerForPush() {
    UIApplication.shared.registerForRemoteNotifications()
  }
}

/// Mantém o iPhone enviando posição com o app fora da tela.
/// O GPS contínuo fica no Geolocator (`allowsBackgroundLocationUpdates`).
/// Aqui só pedimos "Sempre" e seguramos o processo o bastante para o envio
/// ao servidor terminar depois que a tela apaga.
final class SharingLocationKeeper: NSObject, CLLocationManagerDelegate {
  private let manager = CLLocationManager()
  private var channel: FlutterMethodChannel?
  private var pending: FlutterResult?
  private var statusAtRequest: CLAuthorizationStatus?
  private var sharing = false
  private var sessionTask: UIBackgroundTaskIdentifier = .invalid
  private var uploadCount = 0
  private var uploadTask: UIBackgroundTaskIdentifier = .invalid

  func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "br.com.radarfamiliar/location_share",
      binaryMessenger: messenger
    )
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      switch call.method {
      case "requestAlways":
        self.requestAlways(result: result)
      case "start":
        self.start()
        result(nil)
      case "stop":
        self.stop()
        result(nil)
      case "beginUpload":
        self.beginUpload()
        result(nil)
      case "endUpload":
        self.endUpload()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func requestAlways(result: @escaping FlutterResult) {
    let status = manager.authorizationStatus
    if status == .authorizedAlways {
      result("always")
      return
    }
    if pending != nil {
      finish(status)
    }
    statusAtRequest = status
    pending = result
    manager.delegate = self
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(authorizationPromptFinished),
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )
    manager.requestAlwaysAuthorization()
    // Sem diálogo o status não muda e o app continua ativo. Não deixar o
    // Dart esperando. Com o diálogo na tela, o app fica inativo até a escolha.
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
      guard let self, self.pending != nil else { return }
      if UIApplication.shared.applicationState == .active {
        self.finish(self.manager.authorizationStatus)
      }
    }
  }

  @objc private func authorizationPromptFinished() {
    guard pending != nil else { return }
    finish(manager.authorizationStatus)
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    let status = manager.authorizationStatus
    if status == .notDetermined || status == statusAtRequest { return }
    finish(status)
  }

  private func finish(_ status: CLAuthorizationStatus) {
    guard let pending else { return }
    self.pending = nil
    statusAtRequest = nil
    NotificationCenter.default.removeObserver(
      self,
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )
    switch status {
    case .authorizedAlways:
      pending("always")
    case .authorizedWhenInUse:
      pending("whenInUse")
    default:
      pending("denied")
    }
  }

  private func start() {
    sharing = true
    NotificationCenter.default.removeObserver(self)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(didEnterBackground),
      name: UIApplication.didEnterBackgroundNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(willEnterForeground),
      name: UIApplication.willEnterForegroundNotification,
      object: nil
    )
    if UIApplication.shared.applicationState != .active {
      beginSessionTask()
    }
  }

  private func stop() {
    sharing = false
    NotificationCenter.default.removeObserver(self)
    endSessionTask()
    endUpload(force: true)
  }

  @objc private func didEnterBackground() {
    guard sharing else { return }
    beginSessionTask()
  }

  @objc private func willEnterForeground() {
    endSessionTask()
  }

  private func beginSessionTask() {
    guard sessionTask == .invalid else { return }
    sessionTask = UIApplication.shared.beginBackgroundTask(withName: "radar.compartilhar") {
      [weak self] in
      self?.endSessionTask()
    }
  }

  private func endSessionTask() {
    guard sessionTask != .invalid else { return }
    let task = sessionTask
    sessionTask = .invalid
    UIApplication.shared.endBackgroundTask(task)
  }

  private func beginUpload() {
    uploadCount += 1
    guard uploadTask == .invalid else { return }
    uploadTask = UIApplication.shared.beginBackgroundTask(withName: "radar.enviarLocal") {
      [weak self] in
      self?.endUpload(force: true)
    }
  }

  private func endUpload(force: Bool = false) {
    if force {
      uploadCount = 0
    } else {
      uploadCount = max(0, uploadCount - 1)
      if uploadCount > 0 { return }
    }
    guard uploadTask != .invalid else { return }
    let task = uploadTask
    uploadTask = .invalid
    UIApplication.shared.endBackgroundTask(task)
  }
}
