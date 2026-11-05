import 'package:geolocator/geolocator.dart';

enum LocationAccess { granted, denied, serviceOff }

/// Localização só em primeiro plano (protótipo local). O rastreamento em
/// segundo plano entra no M1 atrás de uma interface `LocationEngine`.
class LocationService {
  Future<LocationAccess> ensureAccess() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAccess.serviceOff;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return switch (permission) {
      LocationPermission.always ||
      LocationPermission.whileInUse => LocationAccess.granted,
      _ => LocationAccess.denied,
    };
  }

  Future<Position?> lastKnown() => Geolocator.getLastKnownPosition();

  Stream<Position> positions() => Geolocator.getPositionStream(
    locationSettings: const LocationSettings(distanceFilter: 10),
  );
}
