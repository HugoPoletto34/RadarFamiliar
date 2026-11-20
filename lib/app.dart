import 'package:flutter/material.dart';

import 'core/config/env.dart';
import 'core/di/app_scope.dart';
import 'core/location/location_service.dart';
import 'core/push/push_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/screens/auth_gate.dart';
import 'features/friends/services/friend_service.dart';
import 'features/radar/services/radar_service.dart';

/// Widget raiz da aplicação.
class RadarFamiliarApp extends StatelessWidget {
  const RadarFamiliarApp({
    super.key,
    required this.radarService,
    required this.friendService,
    required this.locationService,
    this.pushService,
  });

  final RadarService radarService;
  final FriendService friendService;
  final LocationService locationService;
  final PushService? pushService;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      radarService: radarService,
      friendService: friendService,
      locationService: locationService,
      pushService: pushService,
      child: MaterialApp(
        title: 'Radar Familiar',
        debugShowCheckedModeBanner: !Env.isProd,
        theme: AppTheme.light,
        home: const AuthGate(),
      ),
    );
  }
}
