import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

enum LocationAccess { granted, backgroundDenied, denied, serviceOff }

const _foregroundDistanceMeters = 10;

/// Cadência com o compartilhamento ligado. O servidor recusa envios com menos
/// de 20 segundos de intervalo; o GPS acompanha esse ritmo mesmo parado.
const _backgroundInterval = Duration(seconds: 25);

const _shareChannel = MethodChannel('br.com.radarfamiliar/location_share');

/// GPS do aparelho. Com o compartilhamento desligado, só em primeiro plano.
/// Ligado, os dois sistemas continuam enviando com o app fora da tela:
/// o Android segura um serviço com notificação; o iPhone exige "Sempre"
/// e o modo de localização em segundo plano. O `startForeground` do
/// Geolocator não declara o tipo `location` e derruba o app no Android 14+.
class LocationService {
  Future<void> _keeperChain = Future<void>.value();
  bool _keeperWanted = false;

  Future<LocationAccess> ensureAccess() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAccess.serviceOff;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      try {
        permission = await Geolocator.requestPermission();
      } on PermissionRequestInProgressException {
        permission = await Geolocator.checkPermission();
      }
    }
    return switch (permission) {
      LocationPermission.always ||
      LocationPermission.whileInUse => LocationAccess.granted,
      _ => LocationAccess.denied,
    };
  }

  /// No iPhone, segundo plano exige "Sempre". O Geolocator só pede
  /// "Ao usar"; o pedido de elevação é nativo, no AppDelegate.
  Future<LocationAccess> ensureBackgroundAccess() async {
    final foreground = await ensureAccess();
    if (foreground != LocationAccess.granted) return foreground;
    if (!_isIos) return LocationAccess.granted;

    if (await Geolocator.checkPermission() == LocationPermission.always) {
      return LocationAccess.granted;
    }
    if (await _requestIosAlways()) return LocationAccess.granted;
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.always) return LocationAccess.granted;
    return LocationAccess.backgroundDenied;
  }

  Future<bool> _requestIosAlways() async {
    try {
      final outcome = await _shareChannel.invokeMethod<String>('requestAlways');
      return outcome == 'always';
    } on Object catch (e) {
      debugPrint('permissão sempre: $e');
    }
    final status = await Permission.locationAlways.request();
    return status.isGranted;
  }

  /// Verdadeiro no iOS quando ainda não há permissão "Sempre".
  Future<bool> needsAlwaysPermission() async {
    if (!_isIos) return false;
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    return await Geolocator.checkPermission() != LocationPermission.always;
  }

  Future<Position?> lastKnown() => Geolocator.getLastKnownPosition();

  Stream<Position> positions({required bool background}) =>
      Geolocator.getPositionStream(
        locationSettings: positionSettings(
          background: background,
          platform: defaultTargetPlatform,
        ),
      );

  /// Android: sobe a notificação do serviço. iPhone: avisa o nativo para
  /// segurar o processo quando a tela apagar. A última intenção é a que vale.
  Future<void> setBackgroundActive(bool active) {
    if (!_isAndroid && !_isIos) return Future<void>.value();
    _keeperWanted = active;
    final wanted = active;
    final run = _keeperChain.then((_) async {
      if (_keeperWanted != wanted) return;
      try {
        await _shareChannel.invokeMethod<void>(wanted ? 'start' : 'stop');
      } on Object catch (e) {
        debugPrint('serviço de localização: $e');
      }
    });
    _keeperChain = run;
    return run;
  }

  /// Janela extra no iPhone para o envio terminar com o app suspenso.
  /// No Android o serviço já mantém o processo acordado.
  Future<void> beginUpload() => _invokeKeeper('beginUpload');

  Future<void> endUpload() => _invokeKeeper('endUpload');

  Future<void> _invokeKeeper(String method) async {
    if (!_isAndroid && !_isIos) return;
    try {
      await _shareChannel.invokeMethod<void>(method);
    } on Object catch (e) {
      debugPrint('serviço de localização: $e');
    }
  }

  Future<bool> openPermissionSettings() => Geolocator.openAppSettings();

  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get _isIos => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
}

/// Configuração do fluxo de GPS. [platform] entra para o teste não depender
/// do aparelho.
@visibleForTesting
LocationSettings positionSettings({
  required bool background,
  required TargetPlatform platform,
}) {
  if (!background) {
    return const LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: _foregroundDistanceMeters,
    );
  }
  return switch (platform) {
    TargetPlatform.android => AndroidSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
      intervalDuration: _backgroundInterval,
    ),
    TargetPlatform.iOS => AppleSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
      activityType: ActivityType.other,
      pauseLocationUpdatesAutomatically: false,
      showBackgroundLocationIndicator: true,
      allowBackgroundLocationUpdates: true,
    ),
    _ => const LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
    ),
  };
}
