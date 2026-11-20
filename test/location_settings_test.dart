import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:radar_familiar/core/location/location_service.dart';

void main() {
  test('segundo plano no Android pede posição periódica', () {
    final settings = positionSettings(
      background: true,
      platform: TargetPlatform.android,
    );

    expect(settings, isA<AndroidSettings>());
    final android = settings as AndroidSettings;
    expect(android.distanceFilter, 0);
    expect(android.intervalDuration, const Duration(seconds: 25));
    expect(android.foregroundNotificationConfig, isNull);
  });

  test('segundo plano no iOS continua com o app suspenso', () {
    final settings = positionSettings(
      background: true,
      platform: TargetPlatform.iOS,
    );

    expect(settings, isA<AppleSettings>());
    final apple = settings as AppleSettings;
    expect(apple.allowBackgroundLocationUpdates, isTrue);
    expect(apple.pauseLocationUpdatesAutomatically, isFalse);
    expect(apple.showBackgroundLocationIndicator, isTrue);
    expect(apple.distanceFilter, 0);
  });

  test('primeiro plano não segura o processo', () {
    final settings = positionSettings(
      background: false,
      platform: TargetPlatform.android,
    );

    expect(settings, isA<LocationSettings>());
    expect(settings, isNot(isA<AndroidSettings>()));
    expect(settings.distanceFilter, 10);
  });
}
